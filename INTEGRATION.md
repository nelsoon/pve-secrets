# Integration with Proxmox VE

Same mechanism as pve-identity: three small points in stock pve-manager
files, applied by the maintainer scripts (`debian/integrate.pl`), idempotent,
removed on uninstall, re-applied by a dpkg trigger when pve-manager replaces
the files. Outcome in `/var/lib/pve-secrets/integration.status`.

1. API registration in `PVE/API2/Cluster.pm` after the Ceph child:
   `PVE::API2::Cluster::Secrets` at path `secrets`.
2. Script tag in `index.html.tpl` loading `/pve2/js/PVESecrets.js` after
   `pvemanagerlib.js`, with a content-hash `ver` suffix.
3. Datacenter navigation entry "Secrets" (needs `Sys.Audit`) in
   `pvemanagerlib.js`, between `// pve-secrets:begin` / `// pve-secrets:end`.

If the API registration fails, the UI points are removed (hidden, not broken).
