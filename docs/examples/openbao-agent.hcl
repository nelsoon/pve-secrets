# OpenBao Agent in a Proxmox guest (VM or LXC), pve-secrets.
# Token file written by pve-identity, refreshed by it:
#   LXC:              /dev/pve-identity/openbao/token
#   VM (vsock agent): /run/pve-identity/openbao/token
#   VM (QGA push):    /var/run/pve-identity/openbao/token
# Replace ADDRESS with the store address shown in Datacenter -> Secrets.

vault {
  address = "https://ADDRESS:8200"
  ca_cert = "/etc/pve-secrets/ca.pem"     # the Proxmox cluster CA (pve-root-ca.pem)
}

auto_auth {
  method "jwt" {
    mount_path = "auth/pve"
    config = {
      role                     = "guest"
      path                     = "/dev/pve-identity/openbao/token"
      remove_jwt_after_reading = false    # the file is read-only and reused
    }
  }
}

template_config {
  static_secret_render_interval = "30s"   # how fast a rotated secret arrives
}

# Pool secret: every guest of the pool can read secret/pool/<pool>/...
template {
  destination = "/run/secrets/db_password"
  perms       = "0400"
  contents    = "{{ with secret \"secret/data/pool/POOL/db\" }}{{ .Data.data.password }}{{ end }}"
}
