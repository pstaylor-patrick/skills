---
name: pst:change
description: Deterministic, config-driven release-gate sweep. Runs all four dockerized audit lanes (k6 load, axe-core accessibility, OWASP ZAP pentest, browserless responsive UX) against a project's change-fabric config, aggregates every finding into one CSV and Markdown report on the Desktop, and records a pass/fail gate for the head commit. Invocable directly and gated into pst:drive.
---

# PST Change (change fabric)

The comprehensive, unattended release-gate sweep. One config file per project
(`.pst/change.yml`) tells the platform how to boot the target app and what to
audit; this skill runs all four dockerized lanes against it and produces one
shareable report pair plus a gate record for the PR's head commit.

Trigger: `/pst:change [<PR, branch, or target description>]`.

Question: would this change survive a release-quality sweep of load,
accessibility, security, and responsive UX, deterministically and on the record?

## pst:change vs pst:qa

Both drive browsers in an ephemeral browserless container, but they are
different tools:

- `pst:qa` is ad hoc, model-scoped, natural-language-driven. It scopes a
  Playwright smoke plan from a described flow, clarifies ambiguity with the
  user, and explores. Use it for exploratory UAT of a specific feature.
- `pst:change` is deterministic and config-driven. It reads `.pst/change.yml`
  and runs a fixed four-lane audit (load, a11y, security, responsive UX) with
  no per-run scoping decisions, meant to run unattended before a
  release-affecting merge. It writes a reproducible report and records a
  pass/fail gate the merge hook enforces.

Reach for `pst:qa` to investigate; reach for `pst:change` to gate.

## The two project files

A change-fabric-integrated repo carries two files, and they split cleanly:

- `.pst/change.yml`: the mechanical target-app config (boot command, health
  check, routes, ZAP scope, k6 thresholds, viewports). See "Config schema".
- `CHANGE.md` at the repo root: the narrative change-management policy (git
  flow, promotion rules, self-review policy, when admin-bypass merging is
  acceptable). See "CHANGE.md". Its machine-checkable subset lives in a
  `change_policy:` frontmatter block the merge gate reads; the prose body is
  the human FAQ a teammate is pointed at. `reference/CHANGE.template.md` is the
  starting point.

The config points at CHANGE.md (via an optional `change_doc:` key, defaulting to
the repo-root `CHANGE.md`); the merge-gating hook reads CHANGE.md's policy block
to decide whether a merge into a protected branch is allowed for the head SHA.

## Workflow

1. **Resolve scope.** A PR (read its head, check it out so the run happens on
   the head commit), a branch, or a target description. The gate record is keyed
   by the git head SHA, so run against the exact commit that will merge.
2. **Confirm the config.** Ensure `.pst/change.yml` exists at the target repo
   root. If it does not, this repo is not change-fabric-integrated yet; say so
   and stop rather than guessing an audit surface. Scoping a target from a
   description follows pst:qa's phase 1-5 shape only where the config leaves a
   choice open; the config is the source of truth for what to audit.
3. **Run the sweep.** From the target repo root:
   `ruby ~/.claude/pst/bin/change_run.rb all`. This boots the app per the
   config, waits for its health signal, stands up the ephemeral runners
   (digest-pinned, `--rm`, per pst:docker), runs k6, a11y, ZAP, and browserless
   lanes, tears everything down, writes the report pair to `~/Desktop`, and
   records the gate under the head SHA. Exit 0 means every lane passed, 1 means
   a lane failed, 2 means a setup failure (no docker, bad config, app never
   ready).
4. **Report.** Summarize the per-lane pass/fail and the failing findings from
   the Markdown report. Name both report paths (the `.md` and the `.csv`) so the
   run is reproducible and shareable.

## Config schema

`.pst/change.yml` (YAML; comments allowed). See
`reference/change.schema.yml` for the annotated, copyable reference. Shape:

- `project`: label used in the report filename.
- `change_doc`: optional path to the policy doc (default `CHANGE.md`).
- `boot`: `up` (boot command, e.g. `docker compose up -d --build ...`), `down`
  (teardown command), `network` (an existing docker network the runners join;
  omit to create an ephemeral one and reach the app via `host.docker.internal`),
  `target_url` (in-network base url the lanes default to), and `health`
  (`url` host-reachable, `expect_status`, `timeout_seconds`).
- `lanes.k6`: `enabled`, `script` (repo-relative k6 script; omit for the
  built-in light-load default), `env`, `thresholds` (`http_req_failed`,
  `http_req_duration`).
- `lanes.a11y`: `enabled`, `routes`, `threshold`
  (`minor|moderate|serious|critical`, default `serious`), optional `base_url`.
- `lanes.zap`: `enabled`, `targets` (list of in-scope urls), `strict` (fail on
  any low-or-above alert; default fails only on high-risk), optional `auth`
  (reserved for authenticated scans; the baseline runs unauthenticated).
- `lanes.browserless`: `enabled`, `routes`, `viewports` (`name`/`width`/
  `height` list), optional `base_url`.

A lane a project does not want is omitted or set `enabled: false`. A project can
carry the config alone with none of the tools installed as repo dependencies.

## CHANGE.md

`reference/CHANGE.template.md` is the template. It is a governance FAQ with a
`change_policy:` frontmatter block (machine-checkable) over a prose body that
answers, per environment, in plain language:

- What is required before a change promotes to each environment (which
  promotion stages require a merge review, which do not).
- Who may review, and whether self-review (the author approving or merging their
  own work, including a tech lead reviewing their own change) is allowed and
  under what conditions.
- When admin-bypass merging (skipping the normal review/CI wait) is and is not
  acceptable, stated as a direct answer, not "sometimes".
- What CI gates at each promotion stage, and whether that gate is ever
  skippable.

The prose is the truth a teammate reads; the frontmatter states the same policy
in the form the merge gate enforces.

## Lane subsets

The single-lane skills run one lane each with the same config and report
shape but record only their own scope (never the comprehensive gate the merge
hook requires): `pst:k6`, `pst:a11y`, `pst:zap`. The browserless responsive
lane has no standalone skill; it runs as part of `pst:change`.

## Failure modes

- Docker unavailable, or a runner image cannot be pulled: `change_run.rb` exits
  2 and names the cause. Report it and stop; never fall back to a host daemon.
- No `.pst/change.yml`: the repo is not integrated. Say so; do not invent a
  target surface.
- The app never becomes healthy: exit 2 with the health url. Report the timeout,
  do not proceed to the lanes.
- A browser lane runs but browserless never becomes ready: the lane records a
  failing finding rather than crashing the whole run.
