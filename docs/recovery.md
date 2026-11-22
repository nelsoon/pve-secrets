# Backup, restore and recovery

## What to keep offline

| Item | Where it comes from | Needed for |
|---|---|---|
| 5 recovery keys (any 3) | shown once by Datacenter → Secrets → Set up | a new admin token; any restore |
| seal key | `pve-secrets export-seal-key` (root, any node) | a restore on a rebuilt cluster |

Keep both in a password manager or on paper, not on the cluster. Raft
snapshots are encrypted by the store: someone who reads the backup storage
learns nothing without the seal key, and the backup storage is not a place
to keep the keys.

## Backups

Datacenter → Secrets → Backup (or `pve-secrets backup-config --storage ID
[--keep N] [--interval HOURS]`). Any PVE storage with `backup` content works;
a shared one (CephFS, NFS) is best. Snapshots land in
`<storage backup dir>/pve-secrets/` as `pve-secrets-<cluster>-<UTC time>.snap`
with a `.sha256` file next to each.

`pve-secrets-backup.timer` runs hourly on every node; only the active node
takes a snapshot, and only when the newest one is older than the interval.
"Back up now" in the panel, or `pve-secrets backup --force`, takes one at once
(PVE task log).

`pve-secrets backup-check` verifies every snapshot (file checksum, archive,
and the checksums inside the snapshot) and exits 1 if one is damaged.

## Lost admin token

Symptom: the panel shows the store healthy but API calls fail with 403, or
`/etc/pve/priv/pve-secrets/admin.token` is gone.

    pve-secrets recover-admin     # paste 3 recovery keys, one per line, then Ctrl-D

This creates a root token from the recovery keys, writes a new admin token,
revokes every older admin token and then the root token.

## Roll back the running store

    pve-secrets restore /path/to/snapshot.snap     # 3 recovery keys on stdin

Everything written after the snapshot is lost. The admin token is replaced.

## Restore on a rebuilt cluster

The cluster has the package installed but no store (Datacenter → Secrets
offers Set up). Do NOT run Set up. On one node, as root:

    pve-secrets restore /mnt/pve/<storage>/dump/pve-secrets/<file>.snap \
        --seal-key seal.txt --vip 192.0.2.10/24 [--name secrets.example.org]
    # paste 3 recovery keys, one per line, then Ctrl-D

`seal.txt` is the output of `export-seal-key` (or the raw 32-byte key). The
command verifies the snapshot, starts a temporary store with the old seal key,
loads the snapshot, restarts OpenBao, and replaces the admin token. The other
nodes wait during the restore and join within a minute after it. Backups
continue to the storage the snapshot was read from.

The store keeps its original recovery keys: the ones you hold stay valid.

If the command stops half-way, fix the cause and run `pve-secrets
recover-admin`, then `rm /etc/pve/priv/pve-secrets/restoring` so the other
nodes start. A node that holds Raft data from before the restore must be
emptied first: `systemctl stop openbao; rm -rf /var/lib/openbao/raft`.
