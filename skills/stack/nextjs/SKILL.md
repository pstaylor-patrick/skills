---
name: stack:nextjs
description: Next.js App Router conventions for PST projects -- RSC, Auth.js, routing patterns.
---

# Next.js Stack Module

Depends on: `react`, `typescript` (both auto-activated).

## App Router conventions

- All routes in `app/`. No `pages/` directory in new projects.
- Server Components (RSC) by default. Add `"use client"` only when browser APIs or interactivity is required.
- Route files: `page.tsx`, `layout.tsx`, `loading.tsx`, `error.tsx`, `not-found.tsx`.
- Collocate component files in the route folder when used only by that route.

## Data fetching

- Fetch in Server Components directly (async component functions). No `useEffect` for data.
- Use `cache()` for deduplication. Use `unstable_cache` for cross-request caching.
- Mutations via Server Actions. No separate API route for form submissions.

## Auth.js (next-auth v5)

- Config in `auth.ts` at project root.
- `AUTH_URL` set to `http://localhost:3000` in dev to avoid OAuth callback mismatches.
- Use `auth()` server-side and `useSession()` client-side. Never pass session as props.

## Environment variables

- Server-only vars: no `NEXT_PUBLIC_` prefix. Never expose secrets to the client bundle.
- Validate all env vars at startup with zod or `@t3-oss/env-nextjs`.

## Performance

- `next/image` for all images. Never `<img>`.
- `next/font` for fonts. No external font CDN requests.
- `next/link` for all internal navigation.
