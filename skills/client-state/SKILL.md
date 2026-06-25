---
name: pst:client-state
description: Redux Toolkit and TanStack Query state management. Auto-applied by the pst shim on every client-state change; also invocable directly.
auto:
  extensions: [js, jsx]
  detect: ["**/*slice.js", "**/*store.js", "**/*query*.js", "**/*api*.js"]
---

# Client State Management Cheat Sheet

Source: Redux Style Guide + Redux Toolkit usage docs + TanStack Query docs

Question: Is server state in Query and client state in Redux with one write path each?

Favor:
- Put server data in TanStack Query.
- Put UI workflow and cross-screen client state in Redux Toolkit.
- Use array query keys only.
- Invalidate or update queries from mutation success paths.
- Keep Redux state serializable.
- Derive with selectors; keep writes in reducers and mutations.
- Keep one canonical owner per datum.

Forbid by default:
- Mirroring query results into Redux state.
- Query keys built from functions, class instances, or unstable objects.
- Non-serializable Redux state or actions.
- Fetching server data in `useEffect` plus `dispatch` when a query fits.
- Global loading flags for query-owned requests.

CI:
- `eslint . --ext .js,.jsx --max-warnings 0`
- `vitest run`
- `! git grep -nE "queryKey:\\s*['\\\"]|new (Map|Set|Date)\\(|useEffect\\(.*dispatch\\(" -- '*.js' '*.jsx'`

Agent protocol:
1. Decide whether each datum is server or client state.
2. Remove duplicated ownership.
3. Tighten query keys, invalidation, and serializability.
4. Preserve behavior.
