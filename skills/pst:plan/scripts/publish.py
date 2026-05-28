#!/usr/bin/env python3
"""Build the studio and publish artifacts to S3 + CloudFront.

Convention over configuration: reads <skill>/plans.config.json for the domain,
AWS profile, and region — then DERIVES everything else. The S3 bucket name
defaults to the domain, and the CloudFront distribution is discovered by its
alias (== domain), so there are no infra IDs in config. Shells out to the `aws`
CLI (same auth the rest of your tooling uses), so no extra Python deps.

  publish.py --skill-dir <path>                 # publish all artifacts
  publish.py --skill-dir <path> --id <id>       # publish, print that one's URL
  publish.py --skill-dir <path> --dry-run       # print the plan, do nothing

Exit codes: 0 ok · 2 config missing/invalid · 3 a shell step failed.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path
from typing import Optional

__all__ = ["Config", "load_config", "discover_distribution_id", "read_slug"]


class Config:
    """Resolved publish settings from plans.config.json."""

    def __init__(self, domain: str, profile: str, region: str, bucket: str) -> None:
        self.domain = domain
        self.profile = profile
        self.region = region
        self.bucket = bucket


def _fail(code: int, msg: str) -> "None":
    print(f"publish: {msg}", file=sys.stderr)
    raise SystemExit(code)


def load_config(skill_dir: Path) -> Config:
    cfg_path = skill_dir / "plans.config.json"
    if not cfg_path.is_file():
        _fail(
            2,
            "no plans.config.json — copy plans.config.example.json and fill in "
            "your domain + awsProfile to enable publishing.",
        )
    try:
        raw = json.loads(cfg_path.read_text())
    except json.JSONDecodeError as exc:
        _fail(2, f"plans.config.json is not valid JSON: {exc}")
    domain = str(raw.get("domain", "")).strip()
    profile = str(raw.get("awsProfile", "")).strip()
    region = str(raw.get("region", "us-east-1")).strip() or "us-east-1"
    if not domain or not profile:
        _fail(2, "plans.config.json needs both 'domain' and 'awsProfile'.")
    bucket = str(raw.get("bucket", "")).strip() or domain
    return Config(domain=domain, profile=profile, region=region, bucket=bucket)


def _aws(cfg: Config, *args: str) -> subprocess.CompletedProcess[str]:
    cmd = ["aws", *args, "--profile", cfg.profile, "--output", "json"]
    return subprocess.run(cmd, capture_output=True, text=True, check=False)


def discover_distribution_id(cfg: Config) -> Optional[str]:
    """Find the CloudFront distribution whose alias == the configured domain."""
    res = _aws(cfg, "cloudfront", "list-distributions")
    if res.returncode != 0:
        _fail(3, f"aws cloudfront list-distributions failed:\n{res.stderr.strip()}")
    try:
        data = json.loads(res.stdout or "{}")
    except json.JSONDecodeError:
        return None
    items = (data.get("DistributionList") or {}).get("Items") or []
    for dist in items:
        aliases = (dist.get("Aliases") or {}).get("Items") or []
        if cfg.domain in aliases:
            return str(dist.get("Id"))
    return None


def read_slug(plans_dir: Path, artifact_id: str) -> str:
    """Pull the cosmetic slug from an artifact's frontmatter (best effort)."""
    for ext in (".mdx", ".md"):
        path = plans_dir / f"{artifact_id}{ext}"
        if path.is_file():
            text = path.read_text()
            match = re.search(r"^permalink:\s*[\"']?([^\"'\n]+)", text, re.MULTILINE)
            if match:
                return match.group(1).strip()
    return artifact_id


def _run(
    cmd: list[str],
    cwd: Optional[Path] = None,
    env: Optional[dict[str, str]] = None,
) -> None:
    print(f"  $ {' '.join(cmd)}")
    res = subprocess.run(cmd, cwd=cwd, env=env, check=False)
    if res.returncode != 0:
        _fail(3, f"command failed ({res.returncode}): {' '.join(cmd)}")


def _build_env(studio: Path) -> dict[str, str]:
    """Env with the studio's node_modules/.bin prepended to PATH, so the build
    finds the local `astro` binary even when `npm run` doesn't augment PATH."""
    node_bin = studio / "node_modules" / ".bin"
    env = dict(os.environ)
    env["PATH"] = f"{node_bin}{os.pathsep}{env.get('PATH', '')}"
    return env


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--skill-dir", required=True, type=Path)
    parser.add_argument("--id", help="artifact id to print the URL for")
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    skill_dir = args.skill_dir.resolve()
    studio = skill_dir / "studio"
    dist = studio / "dist"
    plans_dir = studio / "src" / "content" / "plans"
    cfg = load_config(skill_dir)

    if shutil.which("aws") is None:
        _fail(3, "the `aws` CLI is not on PATH.")

    s3_uri = f"s3://{cfg.bucket}"
    print(f"Publishing to https://{cfg.domain}  (bucket {cfg.bucket}, profile {cfg.profile})")

    if args.dry_run:
        print("  [dry-run] npm run build")
        print(f"  [dry-run] aws s3 sync {dist} {s3_uri} --delete")
        print("  [dry-run] discover distribution by alias + invalidate /*")
    else:
        # Prefer the local astro binary directly — some environments' `npm run`
        # doesn't put node_modules/.bin on PATH. Fall back to the npm script.
        astro_bin = studio / "node_modules" / ".bin" / "astro"
        if astro_bin.exists():
            _run([str(astro_bin), "build"], cwd=studio)
        else:
            _run(["npm", "run", "build"], cwd=studio, env=_build_env(studio))
        if not dist.is_dir():
            _fail(3, f"build produced no dist/ at {dist}")
        # Hashed assets are immutable; HTML must revalidate.
        _run([
            "aws", "s3", "sync", str(dist), s3_uri, "--profile", cfg.profile,
            "--delete", "--exclude", "*.html",
            "--cache-control", "public,max-age=31536000,immutable",
        ])
        _run([
            "aws", "s3", "sync", str(dist), s3_uri, "--profile", cfg.profile,
            "--exclude", "*", "--include", "*.html",
            "--cache-control", "public,max-age=0,must-revalidate",
            "--content-type", "text/html; charset=utf-8",
        ])
        dist_id = discover_distribution_id(cfg)
        if dist_id is None:
            _fail(
                3,
                f"no CloudFront distribution found with alias {cfg.domain}. "
                "Run terraform apply first.",
            )
        _run([
            "aws", "cloudfront", "create-invalidation",
            "--distribution-id", dist_id, "--paths", "/*", "--profile", cfg.profile,
        ])

    if args.id:
        slug = read_slug(plans_dir, args.id)
        print(f"\nPublished: https://{cfg.domain}/p/{args.id}/{slug}")
    else:
        print(f"\nPublished. Browse: https://{cfg.domain}/")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
