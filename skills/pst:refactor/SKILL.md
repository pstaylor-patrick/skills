---
name: pst:refactor
description: Comprehensive Fowler maintainability refactor pass across the entire codebase. An Opus background agent analyzes all code files against the 16-smell rubric in MAINTAINABILITY.md, produces a prioritized smell inventory, then parallel Sonnet agents fix each file in isolated worktrees (behavior-preserving, two hats per rule 15). Run any time you want human maintainability optimized across the board, independent of feature work.
argument-hint: "[path-or-glob] [--report-only]"
allowed-tools: Bash, Read, Edit, Write, Grep, Glob, Agent, AskUserQuestion
---

# /pst:refactor

Comprehensive Fowler code-smell pass. Opus analyzes the full codebase (or a
scoped path), Sonnet fixes each smell in an isolated worktree. Always the
second hat -- behavior stays identical, only structure improves.

## 1. Setup

Resolve the MAINTAINABILITY.md rubric path at runtime:

```sh
LEDGER="$(cat ~/.claude/pst/ledger-path 2>/dev/null)"
MAINT="$(dirname "$LEDGER")/../MAINTAINABILITY.md"
cat "$MAINT"
```

Determine the scan root from `$ARGUMENTS`:

- **Path or glob provided**: scan only that subtree.
- **No argument**: scan the entire repo working tree.

Discover all code files (exclude lockfiles, generated files, docs):

```sh
git ls-files | grep -Ev '\.(lock|snap|min\.(js|css)|pb\.go|pb_test\.go)$' \
  | grep -Ev '^(docs?/|\.github/|dist/|build/)' \
  | grep -E '\.(rb|py|ts|tsx|js|jsx|go|rs|java|kt|swift|ex|exs|cs|cpp|c|h)$'
```

## 2. Opus smell analysis (background)

Spawn one background Opus agent (`model: opus`) with:

- The full content of `MAINTAINABILITY.md` (read via the path resolved above).
- The list of code files from step 1.
- Read every file in the list.
- Instruction:

  ```
  You are a maintainability auditor. For each file, identify which of the 16
  canonical Fowler code smells are present. For every finding, record:
    - file path and approximate line range
    - smell name
    - one-sentence description of the specific instance
    - recommended refactoring (Extract Function, Move Method, etc.)

  Rank findings by impact: smells that would most reduce future change cost
  come first. Smells that require a behavior change to fix (e.g. API redesign
  that breaks callers) are out of scope -- skip them.

  Return a JSON array:
  [
    {
      "file": "path/to/file.rb",
      "smell": "Duplicated Code",
      "lines": "42-61",
      "detail": "Login and signup both inline-validate email format.",
      "fix": "Extract Function: extract validate_email into a shared helper."
    }
  ]
  ```

## 3. Present findings and gate

Group findings by file. Present as a summary table:

```
File                    Smells   Top smell
src/auth/session.rb        3     Duplicated Code (lines 42-61)
src/api/handler.ts         2     Long Function (lines 120-180)
...
```

If no findings: report "No smells detected." and stop.

If `--report-only` was passed, stop here.

Use `AskUserQuestion`: **Apply all fixes in isolated worktrees?** (Yes / Report
only). Treat no objection as Yes.

## 4. Plan gate (foreground)

Determine N from the smell count and file count:

- **Trivial** (1-3 smells, 1-2 files): N=1 -- single Sonnet, skip tournament.
- **Moderate** (4-10 smells or 3-5 files): N=3.
- **Complex** (11+ smells or 6+ files): N=5.

Present smell count and N to the user via `AskUserQuestion`: "Run tournament
with N=\<N\> implementations?" (Yes / Report only / Adjust N). If
`--report-only` was passed, stop here without asking.

## 5. Parallel implementation tournament (background)

Spawn N background Sonnet agents (`model: sonnet`, `isolation: worktree`),
each receiving the same smell findings and target files but a different
strategy directive:

- **Strategy A -- Conservative**: Fix only the highest-impact smells with the
  smallest possible diff. Prefer inlining over new abstractions when the call
  site is nearby. Preserve the existing module and file structure entirely.
- **Strategy B -- Structural**: Reorganize by responsibility. Group related
  behavior together even if it means creating new files or moving methods
  between classes. Optimize for locality of future change.
- **Strategy C -- Extract-first**: Create a named function, class, or module
  for every smell instance. Err toward more abstractions with clear names.
  Every duplicated concept gets a home.

If N=5, add:

- **Strategy D -- Domain-model**: Look for primitive obsession and data clumps;
  introduce domain objects or value types to make implicit business concepts
  explicit.
- **Strategy E -- Functional**: Prefer pure functions and immutable data where
  the language supports it. Move state to the edges. Reduce side-effect surface.

Each agent must:

1. Apply its strategy to fix the smells in the target files.
2. Run existing tests if present; skip any fix that breaks a test and note it.
3. Stage and commit: `git add <changed files> && git commit -m "refactor(<strategy-name>): <primary smell fixed>"`.
4. Include co-author trailer: `Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>`.

## 6. Opus judge selects winner (background)

After all N agents complete, spawn one background Opus agent (`model: opus`)
with:

- All N diffs (collected via `git show HEAD` in each worktree).
- The smell findings from step 2.
- The content of `MAINTAINABILITY.md`.
- Instruction: evaluate each implementation against the six MAINTAINABILITY.md
  outcomes (Higher Cohesion, Lower Coupling, Explicit Intent, Locality of
  Change, Reduced Cognitive Load, Strong Domain Modeling). Score each 1-5 on
  each dimension. Pick the winner.

Return schema:

```json
{
  "winner": "Conservative|Structural|Extract-first|Domain-model|Functional",
  "scores": { "A": 0, "B": 0, "C": 0 },
  "reasoning": "one sentence"
}
```

## 7. Apply and report

Cherry-pick the winning commit to the current branch:

```sh
git cherry-pick <winning-commit-sha>
```

Report: winning strategy, Opus reasoning, scores for each strategy, smells
fixed vs. skipped, and test results.

## Notes

- Rule 24 best-of-N: N=1 for trivial, N=3 for moderate, N=5 for complex.
- Rule 15 two-hats applies to every implementation agent: no behavior changes.
- Rule 7 applies if the result goes to a PR: adversarial review before merge.
- For very large codebases (50+ files), scope with a path first:
  `/pst:refactor src/auth` then widen.
