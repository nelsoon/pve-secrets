# Secrets in VMs and containers

A guest in a PVE pool reads secrets with its pve-identity token: no password,
AppRole secret or other credential is put into the guest.

## Where secrets go

| Path (KV v2 mount `secret/`) | Who can read it |
|---|---|
| `secret/pool/<pool>/...` | every guest in `<pool>` |
| `secret/guest/<vmid>-<gen>/...` | only this guest incarnation |

`<gen>` is the guest's generation from pve-identity. A clone, or a new guest
that re-uses a VMID, has a different generation and does not see the old
guest's secrets; it still sees its pool's secrets. Guests have read access
only. A guest can print its own path:

    cut -d. -f2 /dev/pve-identity/openbao/token | tr '_-' '/+' | base64 -d 2>/dev/null \
      | jq -r '"secret/guest/\(.pve.vmid)-\(.pve.gen)/"'

Write secrets as an administrator, e.g. `bao kv put secret/pool/web/db password=...`.

## How the guest logs in

pve-secrets keeps a jwt auth mount `auth/pve` with role `guest` in sync with
the pve-identity issuer (public keys from `/etc/pve/identity/issuers.d/pve.json`,
so logins do not depend on the issuer host being up; key rotation is picked up
automatically). The token must have `aud=openbao`.

## Guest setup (stock OpenBao Agent)

1. Install the `bao` binary (OpenBao release) in the guest.
2. Copy the Proxmox cluster CA (`/etc/pve/pve-root-ca.pem` on a host) to
   `/etc/pve-secrets/ca.pem`.
3. Use [examples/openbao-agent.hcl](examples/openbao-agent.hcl), with the store
   address from Datacenter → Secrets, your pool, and the token path:
   - LXC: `/dev/pve-identity/openbao/token`
   - VM with the pve-identity agent (vsock): `/run/pve-identity/openbao/token`
   - VM in push mode (guest agent): `/var/run/pve-identity/openbao/token`
4. Run `bao agent -config=/etc/openbao-agent/agent.hcl` as a service. Secrets
   are rendered to `/run/secrets/` (tmpfs); a changed secret arrives within the
   `static_secret_render_interval` (30 s in the example).

Removing a guest from its pool stops new logins at once; a token the agent
already holds stays valid until it expires (1 hour).
