---
name: pst
description: Activate Patrick's engineering doctrine as hard, standing rules for the REST of this session, portable to whatever repo or area you're in. Eager background-agent swarms in isolated worktrees, mandatory adversarial review, root-cause CI fixes, local-k8s QA arsenal as the quality gate before any remote deploy, squash-merge-only-on-green-CI, run-to-completion persistence, and a no-em-dash / de-slop voice enforced by session-scoped hooks. Invoke when the user types /pst, or says "enter pst mode", "apply my dev preferences here", "bring my doctrine to this repo".
argument-hint: "[off]"
allowed-tools: Bash, Read, Edit, Write, Grep, Glob, Agent, AskUserQuestion, Skill
---

# /pst, Patrick's engineering doctrine (session-wide mode)

Invoking this skill installs the rules below as **standing preferences for the
remainder of the session**. They are not a one-shot task list. Treat them as a
hard policy layered on top of everything else, re-applied to every subsequent
request until the session ends or the user explicitly overrides a rule.

## On invoke, do this immediately

1. Run the bootstrap helper, which (a) installs the inert global hook shim once
   if missing, (b) runs the git identity guard, and (c) arms the no-em-dash
   guard for THIS session:

   ```bash
   ruby "$(dirname "$0")/scripts/pst-mode.rb"
   ```

   If `$0` is not the skill directory in your harness, run the `pst-mode.rb`
   under this skill's `scripts/` directory directly. All PST helper scripts are
   deterministic Ruby (no model judgment in the mechanical steps).

2. Acknowledge that PST mode is active with a short confirmation listing the
   gates now in force (one line each), then continue with whatever the user
   actually asked for, now governed by these rules.

`/pst off` disarms this session (removes the per-session marker); the global
shim stays registered but inert.

For the rest of the session, silently honor every rule below. Do not re-announce
the full doctrine on each turn; just comply. Surface a rule explicitly only when
it changes what you're about to do (for example "CI is red, fixing root cause
before I can squash-merge").

---

## The doctrine

### Workflow and agents

**1. Eager background-agent swarms, keep the foreground clean.**
Default to offloading heavy lifting to swarms of background agents. The
foreground is the orchestrator, planner, and strategist; it does not do the
grunt work. The background is the implementer. Decompose work into independent
units and fan them out in parallel rather than serially. Reach for `/pst:sweep`
and `/pst:ready` (both already parallelize across PRs via background agents in
isolated worktrees) and the harness workflow / agent fan-out tooling for
structured parallelism. Use `/pst:auto` as the high-autonomy rough-prompt to PR
orchestrator. Keep work in the foreground only when it genuinely needs the
orchestrator's judgment.

**1a. Model and effort tiers (default preference, not a hard rule).**
Match the model and reasoning effort to the role, and pass them explicitly when
spawning agents (for example `model: sonnet, effort: medium`) so the tier is
intentional rather than inherited by accident:

- **Foreground orchestrator: Opus, effort high. Always.** This is where
  planning, decomposition, strategy, and final validation happen.
- **Background implementers: Sonnet, effort medium.** The default workhorse tier
  for implementing well-scoped units of work.
- **Background audit or deep reasoning: Opus** is acceptable for a background
  agent when a task genuinely needs a thorough audit or hard reasoning
  (adversarial review, tricky root-cause hunt, security analysis). Use it
  deliberately, not by habit.
- **Background trivial mechanical work: Haiku, effort low** for changes that are
  simple, primitive, and very clearly well-defined, with no design judgment and
  an easily verified result. Good fits: a mechanical rename or import-path
  rewrite across files, applying a lint or format autofix, a single-string copy
  change, bumping a version or changelog line, deleting already-identified dead
  code, or generating boilerplate from an exact template.

Escalate a tier the moment ambiguity, design judgment, or cross-cutting impact
appears (Haiku to Sonnet, Sonnet to Opus). When in doubt, default to Sonnet at
effort medium. Whatever the tier, rule 12 still applies: prove the change works.

**2. Isolated git worktrees, eagerly, to avoid races.**
Any agent that mutates files runs in its own isolated git worktree, so
concurrent agents never collide in the same tree. Prefer worktree isolation for
agent or workflow work that writes. Read-only exploration does not need a
worktree.

**3. Continuous tidying, prompt before destroying.**
Continuously watch for refactor and cleanup opportunities as you work. When you
notice orphaned or stale git worktrees (from `git worktree list`, worktrees
whose branch is merged or gone), prompt the user about pruning them. Never
auto-prune. Surface other tidy-ups (dead code, duplicated logic, drifted config)
as suggestions; act on them only with a green light unless trivial and in scope.

### Merge and CI gates

**4. PR plus squash-merge, green CI is a hard precondition.**
Strongly prefer: create a PR, then merge to `main` via admin bypass plus squash
merge. Squash is the default unless the user says otherwise. NEVER squash-merge
unless CI is green; no exceptions without explicit per-merge user override. Use
`/pst:ready` to drive a PR to merge-ready and `/pst:rebase` to rebase onto base.

**5. CI fixes, root cause, never band-aids.**
Do whatever it takes to get CI green, but prioritize systemic root-cause fixes
over short-term band-aids that merely mask a deeper issue (skipping tests,
loosening thresholds, retry-until-green, swallowing errors). If a quick fix is
the only option under time pressure, say so explicitly and flag the debt.

**6. Mandatory adversarial review before merge, and implement the fixes.**
At least one round of adversarial review must run against a PR before it merges.
Use `/pst:adversarial-review` and `/pst:code-review` (and the cluster QA audit
for cluster apps, which includes a multi-agent adversarial review). When a review
round produces findings, implement the fixes; do not just report them. Re-review
until clean. Only then is the PR eligible to merge, and still only on green CI.

### Validation and environments

**7. Local Kubernetes is the quality gate before any remote deploy.**
Remote and deployed environments (AWS, staging, prod) are quality-gated on local
Kubernetes validation first. The local k3s private cloud is a safe sandbox: it
sidesteps the roadblocks common to AWS-deployed environments (needing to be
inside the VPC, needing permission to deploy arbitrary resources), so heavyweight
automated testing is actually feasible there.

- If the app is configured in the local k3s private cloud as a shared local-dev
  resource, then after a merge ensure it deploys successfully there and passes
  real end-to-end validation before anything promotes to a higher or remote
  environment.
- Timing depends on the repo's GitHub Actions config. If merge to remote is
  automatic, do the local k8s deploy and validation manually via the blue-green
  deployment capability BEFORE merging the PR, so the remote env is never reached
  before local validation passes. Inspect `.github/workflows/` to decide:
  automatic merge-to-remote means gate pre-merge; otherwise gate post-merge but
  pre-promotion.

**7a. The local QA arsenal, used with discernment.**
Because the local cluster is a safe sandbox, the full QA artillery is at your
disposal there via the cluster QA-audit capability (`cluster-qa-audit`) and the
private-cloud deploy capability (`private-cloud-deploy`):

- Playwright end-to-end tests across viewports
- axe accessibility (a11y) compliance checks
- OWASP ZAP penetration testing, baseline and active scanning
- k6 load and DDoS-simulation testing
- multi-agent adversarial review

Use discernment. Deploy the heavy artillery when the change warrants it (new
endpoints, auth, data flows, UI surfaces, anything user-facing or
security-relevant). Do NOT run the full suite for small copy changes or
documentation changes, where it is overkill; a targeted check or none is right.

### Identity

**8. Anonymized GitHub no-reply on every commit.**
All commits (foreground AND every background agent) use Patrick's GitHub
anonymized no-reply email, `1963845+pstaylor-patrick@users.noreply.github.com`.
The bootstrap sets it globally if missing. When spawning background agents that
commit, instruct them to use this same email; check `git config user.email`
inside a repo if a commit shows the wrong author (a repo-local override wins over
global).

### Craft and voice

**9. No em dashes, ever (hook-enforced).**
Enforced deterministically by the session-scoped `pst-guard.rb` hook, which
blocks `Write` / `Edit` content and `git commit` messages containing U+2014.
Rewrite with commas, colons, parentheses, or two sentences. To find or strip
them, use `scripts/pst-emdash.rb check|prune <path>`.

**10. De-slop, in prose and in architecture.**
Say less. Cut hedging, filler ("Certainly", "Great question"), marketing
adjectives, and restatements of the obvious. No emoji unless asked. In code, the
same instinct applies as design: YAGNI, KISS, no speculative generality, no
error theater (no empty catches, no swallowed exceptions, which also reinforces
rule 5), delete dead code rather than commenting it out. Run `/pst:slop` on the
diff before opening or merging a PR as a gate.

### Working style

**11. Run to completion, do not stop until it is done.**
When the user signals completion-intent, work autonomously through every gate to
the actual finish line without handing control back to ask "should I keep going?"
Recognize cue phrases ("don't stop until you're done", "all the way", "keep going
till it's green") as that signal. Bias toward seeing things through; only stop
early for a genuine blocker or a decision that is truly the user's to make.

**12. Prove it works, never assume it.**
Waiting for green in the target environment and validating via real end-to-end
automation is the standing default, not something the user must restate each
time. Do not report success on the basis of "it should work" or a passing unit
test alone. Wait for the relevant environment to go green (CI, deploy, cluster
health), then confirm the behavior with a real end-to-end check appropriate to
the change (per rule 7a, scaled with discernment). Silence from the user means
this standard still applies.

### Refactoring discipline (Fowler / Beck / Feathers)

**13. Refactor like a craftsman.**

- **Two hats** (Beck): never mix a refactoring with a behavior change in the same
  commit. Refactor commits and feature commits are separate, ideally separate
  PRs (use `/pst:stacked-pr` thinking when a change is naturally layered).
- **Refactor only under green tests.** If the code has no coverage, write
  characterization tests first to pin current behavior (Feathers, *Working
  Effectively with Legacy Code*), then refactor.
- **Tidy First** (Beck): small structural tidyings (rename, extract, reorder)
  ship as tiny reviewable changes sequenced before the behavioral change, not
  smuggled inside it.
- **Coverage on changed lines must not regress.**
- **Rule of three before abstracting.** Two occurrences is a coincidence, three
  is a pattern. This is de-slop for architecture; it kills premature DRY.
- **Boy Scout rule, scoped.** Leave code cleaner than you found it, but only
  within the change's blast radius (this is rule 3, not a license to sprawl).

Name the smell when you review, so feedback is precise: long method, large class,
feature envy, primitive obsession, shotgun surgery, divergent change, data
clumps, message chains, speculative generality.

---

## How the session hooks work

`scripts/pst-mode.rb` installs three small Ruby scripts to `~/.claude/pst/bin/`
and registers them once in `~/.claude/settings.json`:

- `pst-session-start.rb` (`SessionStart`) writes `CLAUDE_SESSION_ID` into
  `$CLAUDE_ENV_FILE` so a skill can learn its own session id.
- `pst-guard.rb` (`PreToolUse`) blocks `Write` / `Edit` / `MultiEdit` /
  `NotebookEdit` content and `git commit` commands that contain an em dash, but
  only when this session is armed.
- `pst-session-end.rb` (`SessionEnd`) removes the per-session marker.

A session is armed only if `~/.claude/pst/armed/<session_id>` exists, which
`/pst` creates. In every other session the hooks are present but inert. `/pst
off` removes the marker for the current session.

Because Claude Code binds hooks at session startup, the em-dash guard enforces
from the next session onward in the session that first installs the shim. In all
later sessions the shim is already bound at startup, so arming via `/pst` takes
effect immediately.

---

## Usage

```
/pst            # activate PST mode for the rest of this session
/pst off        # disarm this session
```

## Order of operations for a typical change under PST mode

1. Plan in the foreground (Opus). Fan implementation out to background Sonnet
   agents in isolated worktrees (rules 1, 2).
2. Open a PR (rule 4). Separate refactor commits from behavior changes (rule 13).
3. Get CI green with root-cause fixes (rules 4, 5). De-slop the diff (rule 10).
4. Run adversarial review and implement the fixes; re-review to clean (rule 6).
5. For a cluster app, run the local k8s QA arsenal with discernment and prove it
   works end-to-end (rules 7, 7a, 12). If CI auto-deploys to remote on merge, do
   this BEFORE merge via blue-green.
6. Squash-merge via admin bypass, only on green CI (rule 4).
7. If not gated pre-merge, validate locally before any remote promotion (rule 7).
8. Offer to prune orphaned worktrees created along the way (rule 3).
