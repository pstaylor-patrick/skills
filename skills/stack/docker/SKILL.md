---
name: stack:docker
description: Docker conventions for PST projects via OrbStack -- named containers, session reaping.
---

# Docker Stack Module

Aligns with PST doctrine rule 20: all ephemeral infra and dev servers run as OrbStack Docker containers.

## Container naming

Use descriptive names: `<project>-<service>-<purpose>`. Example: `acme-postgres-dev`.

Never use random container IDs for session-tracked containers -- the name is how the session-end hook reaps them.

## Running containers

Prefer `docker run -d --name <name>` over `docker compose` when a single service suffices.

Always specify `--rm` for truly ephemeral containers (one-shot scripts, migrations). Self-cleaning containers do NOT need tracking.

## Session tracking

Register session-scoped containers:

```bash
ruby ~/.claude/skills/pst/scripts/pst-docker.rb register <name>
# with port+subdomain for tailnet proxy:
ruby ~/.claude/skills/pst/scripts/pst-docker.rb register <name> <port> <subdomain>
```

The session-end hook stops and removes tracked containers automatically.

Suppress reaping: `PST_KEEP_DOCKER=1`.

## Caddy proxy (tailnet access)

Start container with `-p <host-port>:<container-port>`. Pick a subdomain under `dev.pstaylor.net`. Add a Caddy route via the admin API. Register with port and subdomain so the reaper can remove the route.
