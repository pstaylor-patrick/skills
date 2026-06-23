---
name: stack:react
description: React conventions for PST projects -- component patterns, hooks, PST-specific rules.
---

# React Stack Module

Depends on: `typescript` (auto-activated).

## Component conventions

- Functional components only. No class components.
- One component per file. File name matches component name (PascalCase).
- Props type declared above the component: `type Props = { ... }`.
- Export the component as a named export. Default exports only at page/route boundaries.

## Hooks

- Custom hooks live in `hooks/` or `lib/hooks/`. Filename: `use<Name>.ts`.
- No hooks in utility files. No business logic in components.
- `useEffect` dependencies must be complete. Use `eslint-plugin-react-hooks`.

## State

- `useState` for local UI state only.
- Lift state up before reaching for a global store.
- Server state (fetching, caching, sync): use React Query or SWR, not `useEffect`+`useState`.

## Performance

- `useMemo` and `useCallback` only when profiling shows a problem. Not as default practice.
- Large lists: virtualize (react-virtual or similar).

## No logic in JSX

Extract conditional rendering to variables or helper components. No ternaries more than one level deep inline in JSX.
