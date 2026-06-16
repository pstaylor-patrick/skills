---
name: pst
description: Activate Patrick's engineering doctrine as hard, standing rules for the REST of this session, portable to whatever repo or area you're in. Eager background-agent swarms in isolated worktrees, mandatory adversarial review, root-cause CI fixes, local-k8s QA arsenal as the quality gate before any remote deploy, squash-merge-only-on-green-CI, run-to-completion persistence, and a no-em-dash / de-slop voice enforced by session-scoped hooks. Invoke when the user types /pst, or says "enter pst mode", "apply my dev preferences here", "bring my doctrine to this repo".
argument-hint: "[off]"
allowed-tools: Bash, Read, Edit, Write, Grep, Glob, Agent, AskUserQuestion, Skill
---

# /pst, Patrick's engineering doctrine (session mode)

Invoking installs the rules below as standing preferences for the rest of the
session, layered over everything else until the session ends or a rule is
overridden. Comply silently; do not re-announce the doctrine each turn; surface a
rule only when it changes what you are about to do. `[HOOK]` marks rules a hook
enforces deterministically (a block or an automatic action); `[NUDGE]` marks
rules a hook reminds about (non-blocking). Detail and examples are in
`REFERENCE.md`.

## On invoke

1. Bootstrap (install the inert global hook shim if missing, git identity guard,
   arm this session): `ruby "$(dirname "$0")/scripts/pst-mode.rb"`
2. Ask the merge mode with `AskUserQuestion`, re-asking on every invoke so it can
   change per repo: **admin-bypass squash** / **auto-merge on approval** /
   **merge-ready only**. Hold the choice for the session. Approval-gated repos
   (for example ShirePath, where Conner must approve) must not be admin-bypassed.
3. Confirm PST mode active in one line plus the chosen merge mode, and state the
   delegate-by-default rule (implementation goes to background worktree agents,
   not inline), then continue.

`/pst off` disarms this session.

## Doctrine

1. **Delegate by default** `[NUDGE]`. Before doing a unit of work inline, test
   it: (1) independent (no live user back-and-forth), (2) well-scoped (clear
   inputs, verifiable done-condition), (3) not a gating judgment (a plan, a
   choice between options, or accept-reject validation). All three yes: spawn a
   background agent in an isolated worktree (Sonnet/medium by default, tier per
   rule 2). Any no: foreground is right. Legitimately foreground: conversational
   replies, planning and decomposition, choosing between options, spawning and
   monitoring and merging agents, final validation, and a lone trivial edit
   (batch several trivial edits to one Haiku agent). The default verb for
   implementation, research, format fixes, and sequential mechanical work is
   delegate; inline work is the exception to justify. Fan out via `/pst:sweep`,
   `/pst:ready`, `/pst:auto`, and workflow.
2. **Model tiers** `[HOOK]` (default, not absolute): foreground Opus/high;
   background implementers Sonnet/medium; Opus only for deep audits; Haiku/low for
   trivial, well-defined mechanical work. Spawns must set an explicit model
   (enforced); escalate on ambiguity; default Sonnet/medium.
3. **Isolated worktrees.** Any file-mutating agent runs in its own worktree.
   Read-only exploration does not.
4. **Tidy, prompt before destroying.** Run `scripts/pst-worktrees.rb`, prompt
   before pruning; never auto-prune. Surface other cleanups as suggestions.
5. **Merge** `[HOOK]`. PR then prefer squash, by the chosen merge mode. A direct
   `gh pr merge` is blocked unless CI is fully green; `--auto` defers to GitHub;
   override `PST_ALLOW_RED_MERGE=1`. `/pst:ready` and `/pst:rebase` assist.
6. **CI root cause.** Fix CI for real; no band-aids that mask the issue. Flag any
   unavoidable quick fix as debt.
7. **Adversarial review before merge** `[HOOK]`. At least one round
   (`/pst:adversarial-review`, `/pst:code-review`); implement findings and
   re-review to clean. Record it with `scripts/pst-reviewed.rb mark` so the merge
   guard allows the merge.
8. **Local k8s gate before remote.** If the app runs in the local k3s cloud,
   deploy and pass real E2E there before any remote (AWS, staging, prod). Gate
   pre-merge via blue-green when CI auto-deploys on merge, else pre-promotion.
9. **QA arsenal, with discernment.** Use `cluster-qa-audit` (Playwright, axe, ZAP
   active, k6) and `private-cloud-deploy` when a change warrants it; skip for copy
   or docs changes.
10. **Identity.** Every commit, including background agents, uses the no-reply
    email `1963845+pstaylor-patrick@users.noreply.github.com`.
11. **No em dashes** `[HOOK]`. Rewrite with commas, colons, parentheses, or two
    sentences. Find or strip with `scripts/pst-emdash.rb check|prune`.
12. **De-slop.** Cut filler, hedging, marketing, restated obvious, emoji. In
    code: YAGNI, KISS, no speculative generality, no error theater, delete dead
    code. Gate with `/pst:slop`.
13. **Run to completion.** On completion-intent ("don't stop until you're done"
    and similar), work autonomously through every gate; stop early only for a
    real blocker or a user-only decision.
14. **Prove it works.** Wait for green in the target environment, then validate
    with real E2E (scaled per rule 9). Never report success from "should work"
    or a passing unit test alone.
15. **Refactor like a craftsman.** Two hats (never mix refactor with behavior
    change), refactor only under green tests (characterization tests first), Tidy
    First, no coverage regression on changed lines, rule of three before
    abstracting. Smell vocabulary in `REFERENCE.md`.
16. **Response brevity** (soft default). Keep each paragraph to 320 characters or
    less and each flat-list bullet to 160 or less; prefer at most 5 bullets. Split
    long prose into multiple short paragraphs rather than one long one.
    Enumerations the user asks for (PR lists, Jira tasks) may exceed the bullet
    count.
17. **Open on post** `[HOOK]`. Actions taken under Patrick's name open in the
    browser so he sees what went out with his face on it: a PR created, a
    PR/issue or Jira comment posted, a Jira issue created, and a PR/issue/Jira
    description updated. Side effect, not a block. Skip a run with
    `PST_NO_BROWSER=1`.

## Usage

`/pst` activates, `/pst off` disarms. Mechanics, merge modes, and rule detail are
in `REFERENCE.md` beside this file; read it only when you need specifics.
