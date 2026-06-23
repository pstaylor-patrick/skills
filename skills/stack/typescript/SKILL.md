---
name: stack:typescript
description: TypeScript conventions for PST projects -- strict mode, type patterns, config.
---

# TypeScript Stack Module

Activated automatically when a project registers the `typescript` stack.

## Config baseline

Every project uses strict mode. `tsconfig.json` should include:

```json
{
  "compilerOptions": {
    "strict": true,
    "noUncheckedIndexedAccess": true,
    "exactOptionalPropertyTypes": true
  }
}
```

## Type patterns

- Prefer `type` over `interface` for object shapes unless declaration merging is needed.
- Never use `any`. Use `unknown` and narrow.
- Explicit return types on exported functions. Inferred types inside implementations.
- Use `satisfies` to validate shapes without widening.
- Avoid type assertions (`as T`). If you need one, add a comment explaining why.

## Import conventions

- Absolute imports from `src/` root (configured via `paths` or `baseUrl`).
- Group: external packages, then internal absolute, then relative. Blank line between groups.
- No barrel files (`index.ts` re-exports) unless the module is a true public API boundary.

## Null handling

- Enable `strictNullChecks` (covered by `strict`).
- Never use `!` non-null assertions on values that could legitimately be null. Narrow instead.
