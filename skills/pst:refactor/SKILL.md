---
name: pst:refactor
description: Standalone Fowler maintainability smell pass on the current diff, a target path, or any staged/unstaged changes. Applies the 16-smell rubric from MAINTAINABILITY.md, presents findings, and optionally implements all fixes as a behavior-preserving refactoring commit (two hats, separate commit per rule 15). Use when you want a dedicated refactor pass independent of any feature work in progress.
argument-hint: "[path-or-glob | --diff | --staged | --report-only]"
allowed-tools: Bash, Read, Edit, Write, Grep, Glob, Agent, AskUserQuestion
---

# /pst:refactor

Dedicated Fowler maintainability pass. Always the second hat -- behavior stays
identical, only structure improves. Use at any point in a session, independent
of feature work in progress.

## Input resolution

Determine what to review from `$ARGUMENTS`:

| Argument              | Target                                                                                |
| --------------------- | ------------------------------------------------------------------------------------- |
| `path`, file, or glob | those files (read in full)                                                            |
| `--diff`              | `git diff HEAD` + full file content for each changed file                             |
| `--staged`            | `git diff --cached` + full file content for each changed file                         |
| _(none)_              | run `pst-smell.rb`; if "required", use `git diff HEAD`; if "skipped", report and stop |

## Steps

### 1. Collect target

Run the input resolution above. For diff-based targets, always read the
**full file** for every changed path -- diffs alone lose the context needed
to spot smells like Duplicated Code or Feature Envy that span unchanged lines.

### 2. Smell pass (Haiku, background)

Spawn a background Haiku agent (`model: haiku`, `effort: low`):

- Load `MAINTAINABILITY.md` from the pst skill directory:
  ```sh
  cat "$(dirname "$(cat ~/.claude/pst/ledger-path)")/../../MAINTAINABILITY.md"
  ```
  Or read it directly: `skills/pst/MAINTAINABILITY.md` in the repo, or
  `~/.claude/commands/pst.md`'s sibling directory resolved at runtime.
- Pass the target file content.
- Instruction: for each of the 16 canonical smells, state whether evidence
  exists in the target. For each hit: smell name, specific code excerpt or
  line reference, recommended refactoring. Skip smells with no evidence.
  Return structured output.

Schema:

```json
{
  "smells": [
    {
      "name": "string",
      "evidence": "string (excerpt or line ref)",
      "refactoring": "string"
    }
  ],
  "clean": "boolean"
}
```

### 3. Gate

- If `clean: true` (no smells): report "No smells detected in target." and stop.
- Otherwise: present findings as a flat list (smell, evidence, fix) under a
  `## Smell findings` header.

If `--report-only` was passed, stop here.

### 4. Plan gate (foreground)

Present the smell count and top finding as a one-line summary. Use
`AskUserQuestion` with: **Implement all fixes in a separate refactoring commit?**
(Yes / Report only). Treat no objection as Yes.

### 5. Implement (Sonnet, isolated worktree)

Spawn a background Sonnet implementer (`model: sonnet`, `effort: medium`,
`isolation: worktree`):

- Target files + smell findings.
- Instruction: apply each refactoring as a **behavior-preserving** transformation.
  Do not change any observable behavior. Run existing tests if present; report
  pass/fail. If a refactoring would break a test, skip it and note it. Produce
  one clean commit:

  ```
  refactor: <short description of primary smell addressed>

  Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
  ```

  Identity per rule 10.

### 6. Report

After the worktree agent completes: list which smells were fixed, which were
skipped (with reason), and whether tests passed. If tests failed on any fix,
name the fix and the failing test.

## Notes

- MAINTAINABILITY.md is the rubric. All 16 smells are in scope regardless of
  file size or diff length (rule 23: a small diff does not exempt a change).
- Two-hats rule (rule 15): if any behavior change crept into the refactoring
  commit, reject it and re-run with a cleaner scope.
- For targets > 500 LOC, prioritize the highest-signal files (those with the
  most smell hits) rather than processing everything at once.
