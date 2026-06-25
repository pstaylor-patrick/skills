---
name: pst:redis
description: Redis cache and session usage. Auto-applied by the pst shim on every Redis-related change; also invocable directly.
auto:
  extensions: [js, mjs]
  detect: [package.json, "**/*redis*.js", "**/*cache*.js", "**/*session*.js"]
---

# Redis Cheat Sheet

Source: Redis command docs + Redis keyspace docs + Redis security docs

Question: Will cache or session failure degrade safely instead of corrupting behavior?

Favor:
- Use Redis for cache, session, rate limit, lock, or queue metadata only.
- Prefix keys as `app:env:domain:id`.
- Set TTL on every cache and session key.
- Use `SET key value EX ... NX` for single-write cache fills and locks.
- Treat misses and outages as recoverable.
- Bound payload size; prefer ids over full documents.
- Use `SCAN` for iteration and bulk maintenance.

Forbid by default:
- `KEYS` in application code.
- `FLUSHALL`, `FLUSHDB`, or `MONITOR` outside ops scripts.
- Cache keys without TTL.
- Using Redis as the source of record.
- Hard-coded Redis URLs or passwords.
- `SETEX` or `SETNX`; use `SET` options instead.

CI:
- `eslint . --ext .js,.mjs --max-warnings 0`
- `! git grep -nE "\\b(KEYS|FLUSHALL|FLUSHDB|MONITOR|SETEX|SETNX)\\b" -- '*.js' '*.mjs'`

Agent protocol:
1. Decide whether the key is cache, session, or coordination.
2. Add names, TTLs, and failure fallbacks.
3. Remove blocking and deprecated commands.
4. Preserve behavior.
