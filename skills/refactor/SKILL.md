---
name: pst:refactor
description: Run a behavior-preserving refactor over a PR, branch, repo, file, or glob using all applicable pst rubrics.
---

# Refactor Agent

Question:
What is the smallest change that improves maintainability without changing behavior?

Scope:
- PR
- Branch
- Repository
- File
- Glob

If scope is ambiguous:
- Ask.
- Do not guess.

Process:
1. Resolve scope to files.
2. Route files through applicable pst skills: `ruby ~/.claude/pst/bin/skill_route.rb <files...>`.
3. Apply each skill's rubric.
4. Preserve behavior.
5. Verify with tests/build.
6. Report changes.

Protocol:
1. Identify the smell.
2. Identify the change risk.
3. Apply the smallest refactoring.
4. Verify behavior.
5. Stop before redesigning.
