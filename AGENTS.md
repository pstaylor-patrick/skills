# Skills Repository

Reusable workflow skills for Claude Code, OpenAI Codex, and Pi Coding Agent.

## Compatibility

- Source skills live in `skills/<name>/SKILL.md`.
- Claude Code installs them as slash-command symlinks in `~/.claude/commands/`.
- OpenAI Codex installs them as skill directory symlinks in `~/.codex/skills/`.
- Pi installs portable wrapper skills in `~/.pi/agent/skills/` with Agent Skills-safe lower-kebab names.
  - Example: `pst:push` becomes `/skill:pst-push` in Pi.
- When adding a new skill, update the `SKILLS` array in `install.sh` and the README.

## Skill architecture

Three tiers compose into per-project behavior:

1. **Global shim** (`skills/pst/`): always-on hooks (SessionStart, UserPromptSubmit, PreToolUse, PostToolUse, SessionEnd). Inert until armed. Invoke `/pst` to arm a session.

2. **Stack modules** (`skills/stack/<name>/`): per-language/framework rules. Eight modules: typescript, ruby, docker, terraform, react, rails, nextjs, aws. Deps: react depends on typescript, rails depends on ruby, nextjs depends on react and typescript, aws depends on terraform. Auto-activated by project layer.

3. **Project layer**: repo-local `.pst/project.json` or user-global `~/.claude/pst/projects.json` binds a project name to a stack list. SessionStart auto-arms the matching stacks. Unregistered repos trigger an onboarding flow.

Install: `./install.sh` (installs for Claude Code, Codex, and Pi).

## Development

- Keep skill frontmatter valid Agent Skills YAML where possible.
- Prefer harness-neutral instructions. If a workflow depends on a harness-specific tool, include a fallback path for other harnesses.
- Do not commit local secrets such as `.env`.
