# ctx-nas

The NAS-side git transport for the pst:ctx context store: a Forgejo server joined
to the tailnet by a real tailscaled sidecar, deployed on a Synology NAS via
Container Manager. The two share one network namespace, so Forgejo is reachable
only over the tailnet, never the LAN.

This directory is the source of truth for the deployment. It is NOT installed by
`install.rb` (that wires the local agent shim); deploying is a manual Container
Manager step, because the compose runs on the NAS, not on a Mac.

## Secrets

None live here. `docker-compose.yml` ships a placeholder `TS_AUTHKEY`; set the
real value (a reusable Tailscale auth key tagged `tag:ctx`) from your secret store
at deploy time. The Forgejo access token is minted after first-run and kept in
your secret store, never committed.

## Deploy

1. Create the shared folder `pst-ctx` (`/volume1/pst-ctx`), Read/Write for the
   dedicated non-admin owner and admin only. Create `ts-state/` and `forgejo/`
   under it.
2. In Container Manager, create a project named `ctx` from `docker-compose.yml`,
   with the real auth key substituted in.
3. Build the project. The sidecar registers as tailnet node `pst-ctx`; Forgejo
   serves on `:3000` over the tailnet.
4. First-run Forgejo over the tailnet: create the admin user, create an org for
   the per-project repos, disable registration (already set), and mint a
   read/write access token. Save the token to your secret store.

## Two host fixes a fresh deploy needs

Both are one-time, applied as the DSM admin account over SSH, and both must be
made to persist across reboot with a Task Scheduler boot-up task.

### 1. /dev/net/tun is missing

The Synology host has no `/dev/net/tun` by default, so the sidecar fails with
`error gathering device information while adding custom device "/dev/net/tun"`.
Create it:

```bash
mkdir -p /dev/net
mknod /dev/net/tun c 10 200
chmod 600 /dev/net/tun
```

Persist (Control Panel > Task Scheduler > Triggered Task > Boot-up, run as root):

```bash
mkdir -p /dev/net; [ -c /dev/net/tun ] || mknod /dev/net/tun c 10 200; chmod 600 /dev/net/tun
```

If `mknod` alone does not let the sidecar start, the `tun` kernel module is not
loaded; load it before creating the node.

### 2. Forgejo /data ownership

File Station creates `/volume1/pst-ctx/forgejo` with a Synology ACL and a 000
POSIX mode owned by the creating user, but the Forgejo image runs as uid 1000.
Forgejo then crash-loops on `stat /data/gitea/conf/app.ini: permission denied`.
Hand the directory to uid 1000 as plain POSIX:

```bash
synoacltool -del /volume1/pst-ctx/forgejo
chown -R 1000:1000 /volume1/pst-ctx/forgejo
chmod -R 700 /volume1/pst-ctx/forgejo
```

The sidecar works without this because it runs as root over a plain-POSIX
`ts-state/`; only the non-root Forgejo hits the ACL.

## Base image tags

`tailscale:stable` and `forgejo:9` are rolling tags, chosen so the unattended
appliance receives security patches without manual bumps. Pin to a digest if
reproducibility is preferred over auto-patching.
