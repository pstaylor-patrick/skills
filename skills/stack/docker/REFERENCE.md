# Docker Reference

## Common commands

- `docker ps` -- list running containers
- `docker logs -f <name>` -- follow logs
- `docker stop <name> && docker rm <name>` -- manual reap
- `docker exec -it <name> bash` -- shell into container

## OrbStack

OrbStack replaces Docker Desktop on macOS. Same CLI, faster VM. Containers visible at `<name>.orb.local`.
