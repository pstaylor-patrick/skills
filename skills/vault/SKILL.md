---
name: vault
description: Manage isolated encrypted-vault OrbStack VMs ("floofy-garden"). Use when the user wants to spin up a new encrypted workspace VM, import/export files into an encrypted vault, open/lock a vault, or check vault status. Triggers include "new vault", "spin up a VM for X", "put this file in my <name> vault", "open my recovery vault", phrases mentioning a vault by area/name (e.g. personal/recovery), or any request to move files into/out of an isolated encrypted workspace.
---

# Vault: isolated encrypted-workspace VMs

Each **vault** is its own OrbStack Linux machine (created with `--isolated`, so it
cannot see the host filesystem) holding a **gocryptfs** encrypted volume. Plaintext
only ever exists inside the running VM; the host sees ciphertext only. Vaults are
grouped into **areas** (e.g. `personal`). The machine name is always `<area>-<name>`.

All operations go through one deterministic Ruby CLI: **`~/bin/vault`** (on PATH as
`vault`). This skill's job is to translate the user's natural-language request into
the right `vault` subcommand, run it via Bash, and report the result. Do not
re-implement the logic: always shell out to `vault`.

## Subcommands

| Intent | Command |
| --- | --- |
| Create a new encrypted vault VM | `vault new <area>/<name> [--desc "text"]` |
| Open / enter a vault (unlocks + shell) | `vault open <area>/<name>` |
| Lock (unmount) a vault | `vault lock <area>/<name>` |
| Import host file(s) into a vault | `vault import <area>/<name> <file>...` |
| Export file(s) out to the host outbox | `vault export <area>/<name> <relpath>...` |
| Drain the host dropzone into the vault | `vault inbox <area>/<name>` |
| Start the AWS credential broker (servant) | `vault aws-broker <area>/<name> --profile <aws-vault-profile>` |
| Show machine + lock state | `vault status [<area>/<name>]` |
| List configured vaults | `vault list` |
| Delete a vault VM (asks to confirm) | `vault destroy <area>/<name>` |

## How to handle common requests

- **"Create/spin up a vault for X in <area>"** - pick a short kebab-case `<name>`,
  run `vault new <area>/<name> --desc "<what it's for>"`. Then tell the user:
  (1) run `source ~/.zshrc` (or open a new terminal) so the `<name>` alias works,
  (2) the first time they run `claude` inside the VM they must log in once.
  `vault new` is idempotent (safe to re-run if it was interrupted).

- **"Put this file in my <name> vault: <path>"** - `vault import <area>/<name> <path>`.
  The host source file is left in place; mention that so the user can delete it if
  they want it gone from the host. If the user only gives the vault short name and
  it's unambiguous in `vault list`, use that area; otherwise ask which area.

- **"Get <file> out of my <name> vault"** - `vault export <area>/<name> <relpath>`.
  The file lands in `~/vault-outbox/<area>-<name>/`; report that path.

- **"I dropped files in the folder"** - the dropzone is `~/vault-inbox/<area>-<name>/`.
  Run `vault inbox <area>/<name>` to move them into the encrypted vault.

- **"Open / lock / status"** - the matching subcommand. Note: `vault open` starts an
  interactive shell, so when YOU (Claude) need to run something inside a vault
  non-interactively, prefer `vault import/export/inbox`, or
  `orb -m <area>-<name> -- bash -lc '<cmd>'` after ensuring it's unlocked.

## Overlays (per-area / per-machine extra tooling)

Beyond the global base deps, vaults can get extra tooling from **overlays** in
`~/.vaults/overlays/`: `<area>.sh` runs for every vault in that area, and
`<area>-<name>.sh` for one machine. They run after base provisioning on `vault new`
(idempotent). To change tooling for an area, edit its overlay and re-run `vault new`.

- **`servant` overlay** adds: AWS CLI v2, GitHub CLI, the AWS broker client
  (`credential_process`), and `repo-mirror`.

## AWS access (servant): host-side broker

Servant VMs hold **no AWS keys**. `aws` uses `credential_process` to fetch
short-lived assume-role creds from a host broker:

1. One-time host setup (user does this, with real secrets):
   `aws-vault add <profile>` then add a role-assuming profile to `~/.aws/config`.
2. Start the broker (keep it running during AWS work):
   `vault aws-broker servant/<name> --profile <profile>`
3. Inside the VM, `aws ...` just works while the broker runs. Ctrl-C the broker to
   revoke VM access (it deletes the handoff env file).
- Test the wiring without real keys: `vault aws-broker servant/<name> --mock` then
  run `aws sts get-caller-identity` in the VM (expect `InvalidClientTokenId`).

## GitHub (servant)

One account, multiple orgs. Inside the VM (vault unlocked) run `gh auth login` once;
the token is stored encrypted in the vault (`GH_CONFIG_DIR=~/vault/.gh`). Mirror
repos across orgs with `repo-mirror <src-owner/repo> <dst-owner/repo>`. For CI/CD,
prefer GitHub Actions OIDC - AWS IAM roles (no static keys in workflows).

## Notes & gotchas

- The vault password is a random secret stored in the **macOS Keychain**
  (`service: floofy-garden`, `account: <area>-<name>`) and piped into the VM over
  stdin at unlock time: never run `claude`/commands that would print it.
- Base deps in every VM: git, Python 3, Ruby, **Node LTS + Claude Code**, gocryptfs.
  Defined once in `~/.vaults/provision.sh` (idempotent). To add a base dependency
  for all future vaults, edit that file.
- Clipboard: inside a VM, `pbcopy` (or `clip`) pushes stdout to the macOS clipboard
  via OSC52; paste is normal Cmd+V. Requires an OSC52-capable terminal
  (iTerm2/Ghostty/kitty, not stock Terminal.app).
- Config registry: `~/.vaults/config.yaml`. Per-vault zsh aliases: `~/.vaults/aliases.zsh`.
