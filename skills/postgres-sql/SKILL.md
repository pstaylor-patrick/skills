---
name: pst:postgres-sql
description: PostgreSQL schema and SQL changes. Auto-applied by the pst shim on every SQL migration change; also invocable directly.
auto:
  extensions: [sql]
  detect: ["db/**/*.sql", "migrations/**/*.sql", "prisma/migrations/**/migration.sql"]
---

# PostgreSQL and SQL Cheat Sheet

Source: PostgreSQL docs + OWASP SQL Injection Prevention Cheat Sheet

Question: Does the schema enforce invariants and let writes stay online?

Favor:
- Enforce invariants with `PRIMARY KEY`, `UNIQUE`, `FK`, `CHECK`, and `NOT NULL`.
- Add indexes for new foreign keys and hot predicates.
- Parameterize values with placeholders.
- Use explicit transactions for multi-statement writes.
- Use `INSERT ... ON CONFLICT` for idempotent upserts.
- Backfill in batches before tightening constraints.
- Use `CREATE INDEX CONCURRENTLY` or `DROP INDEX CONCURRENTLY` on large live tables.

Forbid by default:
- String-built SQL with interpolated values.
- `SELECT *` in application queries.
- `SERIAL`; prefer `GENERATED ... AS IDENTITY`.
- `DELETE` or `UPDATE` without `WHERE` outside migrations.
- Long transactions around network I/O.
- Lock-heavy table rewrites without phased rollout.

CI:
- `sqlfluff lint --dialect postgres`
- `! git grep -nE "SELECT \\*|\\bSERIAL\\b|\\bDROP TABLE\\b|\\bTRUNCATE\\b" -- '*.sql'`

Agent protocol:
1. Encode invariants in DDL, not app code.
2. Make online changes in phases.
3. Parameterize every value and bound every write.
4. Preserve behavior.
