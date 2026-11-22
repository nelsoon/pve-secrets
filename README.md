# pve-secrets

A highly available [OpenBao](https://openbao.org) secret store that lives on
the nodes of a Proxmox VE cluster. Guests in a resource pool log in with their
[pve-identity](https://github.com/nelsoon/pve-identity) token, so no secret,
password or AppRole credential is ever copied into a guest.

Status: v0.1, store bring-up (HA, unattended unseal, audit) and the
Datacenter setup/status panel. Guest
bindings, backup, the Proxmox API and panel, and Kubernetes come next.

## How it runs

- OpenBao on every PVE node, Raft storage on local disk (never on Ceph).
  Nodes join automatically, including nodes added later; the first 5 nodes
  are voters. 3 nodes survive the loss of one; 1–2 nodes run without fault
  tolerance and `pve-secrets status` warns about it.
- Unseal without a human: a static seal key in `/etc/pve/priv/pve-secrets/`
  (root only, replicated by pmxcfs), handed to OpenBao by systemd
  `LoadCredential=`. Root on a PVE host is trusted, as it already can read
  every guest disk. Recovery keys (3 of 5) are shown once at init: keep them
  offline.
- TLS certificates from the PVE cluster CA, one per node.
- One address for clients: a VRRP address held by a node whose OpenBao is
  unsealed (its own keepalived instance, independent of any other).
- Audit: every request is logged to `/var/log/openbao/audit.log` (0600) on the
  node that handled it, rotated daily.
- Starts before `pve-guests.service`.

## Install

On every node:

```sh
apt install ./openbao_2.7.*_linux_amd64.deb ./pve-secrets-manager_*_all.deb
```

Once per cluster: **Datacenter → Secrets → Set up** (needs `Sys.Modify` on
`/`), giving the client address (VRRP, CIDR) and optionally a DNS name. The
recovery keys are shown once in that dialog, with Download and Copy; the
dialog only closes after you confirm you saved them. They are not stored
anywhere. Same from the shell:

```sh
pve-secrets init --vip 192.0.2.10/24 [--name secrets.example.net]
pve-secrets status
```

API: `GET /cluster/secrets/status` (`Sys.Audit`), `POST /cluster/secrets/init`
(`Sys.Modify`, synchronous so the keys never reach a task log).

Clients use `https://<vip>:8200` with the PVE cluster CA
(`/etc/pve/pve-root-ca.pem`). The admin token for the Proxmox side is in
`/etc/pve/priv/pve-secrets/admin.token`.

## Uninstall

Removing the package stops the timer and the VRRP address. Purging keeps the
store data (`/var/lib/openbao`), `/etc/pve/secrets.cfg` and
`/etc/pve/priv/pve-secrets/`: deleting them destroys every secret.

## Build

```sh
make lint deb
```

## License

AGPL-3.0-or-later.
