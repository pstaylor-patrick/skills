---
name: pst:adversarial-review
description: Plan a subject, emit an adversarial-review prompt + changelog stub, and eagerly implement on a draft PR
argument-hint: "<what-to-plan-and-build> [--impl-now|--no-impl]"
allowed-tools: Bash, Read, Edit, Write, Grep, Glob, Skill
---

# Adversarial-review-driven plan + build

Take a subject/goal, produce a **phased plan**, hand the user a self-contained
**adversarial-review prompt** to run against another model (Codex, etc.), open a
**changelog stub** for that reviewer to fill, then **eagerly implement the plan
on a dedicated draft PR without waiting for the review to come back**. When the
user returns the changelog, fold its fixes into both the plan and the in-flight
implementation.

The premise: the slowest part of a high-quality build is round-tripping a plan
through critique. So run the critique **in parallel** with implementation —
start building the low-churn foundations immediately (they rarely change), and
absorb the adversarial findings as they arrive.

---

## Quick reference

```bash
/pst:adversarial-review "a rate limiter for the public API"        # plan + review prompt + start building
/pst:adversarial-review "migrate auth to Better Auth" --no-impl    # plan + review prompt only, do NOT start building yet
/pst:adversarial-review "redesign the billing webhook handler" --impl-now  # skip confirmation, jump straight to implementation
/pst:adversarial-review <changelog-path-or-paste>                  # second invocation: apply returned changelog to plan + impl
```

Three artifacts get written to a per-subject working dir and opened in VS Code:

| File                           | Who writes it                                  | Purpose                                                                         |
| ------------------------------ | ---------------------------------------------- | ------------------------------------------------------------------------------- |
| `PLAN.md`                      | this skill (then the reviewer edits it inline) | phased plan: scope, design options + recommendation, risks, acceptance criteria |
| `ADVERSARIAL-REVIEW-PROMPT.md` | this skill                                     | self-contained prompt to paste into another model                               |
| `CHANGELOG.md`                 | the adversarial reviewer                       | one entry per change, with rationale                                            |

Flags: `--impl-now` skips the "start building?" confirmation; `--no-impl`
produces the three artifacts and stops (no PR yet).

---

## Step 0 — derive paths and slug (do this first, at runtime)

Never bake absolute paths in. Derive everything from the current repo and the
subject.

```bash
# Repo root (fall back to cwd if not a git repo).
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

# Slug from the subject: lowercase, non-alnum -> '-', collapse + trim, cap length.
SUBJECT="<the argument text>"
SLUG="$(printf '%s' "$SUBJECT" \
  | tr '[:upper:]' '[:lower:]' \
  | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//' \
  | cut -c1-50)"

# Prefer the repo's docs/plans/<slug>/; fall back to a scratch dir outside the repo
# if the repo has no docs/ convention or you do not want plan files committed.
if [ -d "$REPO_ROOT/docs" ]; then
  WORKDIR="$REPO_ROOT/docs/plans/$SLUG"
else
  WORKDIR="${TMPDIR:-/tmp}/adversarial-review/$SLUG"
fi
mkdir -p "$WORKDIR"
```

Tell the user the chosen `WORKDIR` and slug. If `docs/plans/` would be committed
and the user does not want plans in the repo, switch to the scratch dir.

---

## Step 1 — write the phased PLAN and open it

Author `"$WORKDIR/PLAN.md"`. It must be a genuine plan, not a stub. Required
sections:

- **Subject / goal** — one paragraph restating what we are building and why.
- **Scope** — explicitly in-scope and out-of-scope bullets (out-of-scope is what
  stops scope creep; be generous here).
- **Phases** — numbered, each with: objective, concrete tasks, the artifacts/files
  touched, and an estimate of churn risk (low/medium/high — drives build order).
- **Design options + recommendation** — at least two viable approaches with
  tradeoffs, then a clear recommendation and the reasoning.
- **Risks & failure modes** — what could go wrong (correctness, security, perf,
  data loss, scope, ops) and the mitigation for each.
- **Acceptance criteria** — testable, checkbox-style. This is what "done" means.
- **Open questions** — anything genuinely undecided.

Then open it (reuse the window for subsequent tabs):

```bash
code "$WORKDIR/PLAN.md"
```

---

## Step 2 — write the ADVERSARIAL-REVIEW-PROMPT and open it

Author `"$WORKDIR/ADVERSARIAL-REVIEW-PROMPT.md"` as a **self-contained** prompt
(the reviewer model will not have this repo's context, so spell everything out).
It must instruct the reviewer to:

1. **Attack the plan.** Hunt for failure modes, hidden/unstated assumptions,
   security holes, correctness bugs, scope creep or under-scoping, missing edge
   cases, race conditions, and operational gaps. Be adversarial, not polite.
2. **Edit the PLAN inline.** Make concrete improvements directly in `PLAN.md` —
   tighten scope, fix design flaws, add missing phases/criteria. Not a separate
   review doc; the plan itself gets better.
3. **Emit a CHANGELOG.** Append to `CHANGELOG.md` one entry per change, each with
   _what changed_ and _why_ (the rationale is mandatory — a change with no reason
   is rejected).

Use this template (fill the bracketed bits at runtime):

```markdown
# Adversarial review request

You are an adversarial reviewer. Your job is to find everything wrong with the
plan in `PLAN.md` (in this same directory) and make it materially better.

## Context (self-contained — assume no other knowledge of this project)

[Paste/summarize: what the project is, the relevant stack, constraints, and the
goal from PLAN.md's Subject section. Enough that the reviewer needs nothing else.]

## What to do

1. **Attack the plan.** Find failure modes, hidden assumptions, security and
   correctness risks, scope problems (creep AND gaps), missing edge cases, race
   conditions, and operational/rollback gaps. Assume it is wrong until proven.
2. **Edit `PLAN.md` inline.** Apply concrete improvements directly in the file —
   tighten scope, fix design choices, add phases/risks/acceptance criteria as
   needed. Do not write a separate review document; improve the plan itself.
3. **Write `CHANGELOG.md`.** For every change you made, append one entry:
   - **What:** the concrete change (section + before→after in a sentence).
   - **Why:** the rationale — the risk it removes or the gap it fills.
     A change with no rationale is not allowed. Order entries most-impactful first.

## Output

- An edited `PLAN.md` (improved in place).
- A populated `CHANGELOG.md` (one rationale-bearing entry per change).
- A 3-5 bullet summary of the most serious problems you found.
```

Open it in the same window:

```bash
code -r "$WORKDIR/ADVERSARIAL-REVIEW-PROMPT.md"
```

---

## Step 3 — open the CHANGELOG stub

Author `"$WORKDIR/CHANGELOG.md"` as an empty-but-headed stub, then open it:

```markdown
# Changelog — adversarial review of: [subject]

> This file is populated by the **adversarial reviewer** (see
> `ADVERSARIAL-REVIEW-PROMPT.md`). One entry per change, each with a rationale.
> Leave it empty until the review runs.

<!-- entries appended here by the reviewer -->
```

```bash
code -r "$WORKDIR/CHANGELOG.md"
```

Tell the user: "Paste `ADVERSARIAL-REVIEW-PROMPT.md` into Codex/another model
pointed at `$WORKDIR`. When it returns the edited plan + changelog, re-run
`/pst:adversarial-review <changelog-path>` and I will fold the fixes in."

If `--no-impl` was passed, **stop here**. Otherwise continue to Step 4.

---

## Step 4 — eagerly implement on a dedicated draft PR (do NOT wait for the review)

This is the point of the skill: build in parallel with the critique. Unless
`--impl-now` was passed, confirm once ("Start implementing now on a draft PR
while the review runs?"), then proceed.

### 4a. Branch + worktree

Work in isolation so the user's current checkout is undisturbed:

```bash
BRANCH="feat/$SLUG"
git -C "$REPO_ROOT" fetch origin
# Base off the repo default branch (origin/main or origin/master).
BASE="$(git -C "$REPO_ROOT" symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's#^origin/##')"
BASE="${BASE:-main}"
git -C "$REPO_ROOT" worktree add ".worktrees/$SLUG" "origin/$BASE" -b "$BRANCH"
# If branch/worktree exists, append a numeric suffix: feat/<slug>-2, etc.
IMPL_DIR="$REPO_ROOT/.worktrees/$SLUG"
```

### 4b. Build order — foundations first

Implement **lowest-churn phases first** (the ones the adversarial review is least
likely to overturn): types/interfaces, schema, config scaffolding, pure helper
functions, test harness. Defer anything the review might reshape (public API
surface, contentious design choices) until either the changelog lands or it
becomes blocking. Commit incrementally with conventional messages:

```bash
git -C "$IMPL_DIR" add <specific files>
git -C "$IMPL_DIR" commit -m "feat(<slug>): <phase objective>"
```

### 4c. Open the draft PR early

Push and open a **draft** PR so progress is visible and CI runs. Use a heredoc
body file (never `--body "...\n..."` — escaped newlines post literally):

```bash
git -C "$IMPL_DIR" push -u origin "$BRANCH"
cat > "${TMPDIR:-/tmp}/pr-body-$SLUG.md" <<EOF
## Summary

Implements: $SUBJECT

This PR is being built **in parallel** with an adversarial review of the plan
(\`$WORKDIR/PLAN.md\`). Foundational/low-churn pieces land first; design-sensitive
work follows once the review changelog is in.

## Status

- Plan: \`$WORKDIR/PLAN.md\`
- Adversarial review: in flight (\`$WORKDIR/CHANGELOG.md\` pending)

## Test plan

- [ ] (acceptance criteria from PLAN.md, transcribed here)
EOF
gh pr create --draft --base "$BASE" --head "$BRANCH" \
  --title "feat: $SUBJECT" --body-file "${TMPDIR:-/tmp}/pr-body-$SLUG.md"
gh pr view --web
```

> **Optional — delegate to a background agent.** The implementation can be handed
> to a background agent running in the `$IMPL_DIR` worktree so it proceeds while
> the user runs the adversarial review elsewhere. If you do this, hand the agent
> the plan path, branch, base, and the "foundations-first" build order, and have
> it commit incrementally and keep the draft PR updated.

---

## Step 5 — adapt when the changelog returns (second invocation)

When the user re-runs `/pst:adversarial-review <changelog-path-or-paste>`:

1. **Read the changelog and the edited PLAN.** Each entry is a concrete change +
   rationale.
2. **Reconcile the plan.** The reviewer edited `PLAN.md` inline; confirm those
   edits are coherent and resolve any conflicts with what you have already built.
3. **Apply fixes to the in-flight implementation eagerly.** For each changelog
   entry that affects code, make the change in `$IMPL_DIR`, commit it with a
   message referencing the rationale (e.g.
   `fix(<slug>): tighten X per adversarial review — <why>`), and update the draft
   PR's test plan if acceptance criteria changed.
4. **Push and refresh.** `git -C "$IMPL_DIR" push --force-with-lease` if you had
   to rewrite history; otherwise a normal push. Refresh the PR body via
   `gh pr edit --body-file` (heredoc), then `gh pr view --web`.
5. **Flip out of draft** once the foundations + adversarial fixes are in and the
   acceptance criteria are met: `gh pr ready`.

---

## Conventions (this repo / Patrick)

- VS Code via the `code` CLI; `code -r` to reuse the window for extra tabs.
- PR/issue bodies via `--body-file` with a heredoc — never `--body "...\n..."`.
- Updates that rewrote history use `git push --force-with-lease`, never `--force`.
- Keep generated paths runtime-derived; never hardcode machine-specific absolutes.
- Do not commit secrets or scratch plan files you did not mean to (scratch dir
  default lives outside the repo).
