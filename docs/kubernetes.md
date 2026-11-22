# Kubernetes clusters

Pods authenticate with their own service-account token (projected,
`audience: openbao`). No long-lived token reviewer credential is stored in
OpenBao: pve-secrets trusts the cluster's service-account issuer keys.

## Registering a cluster

Whoever manages the cluster (the pve-k8s manager, on create and after every
service-account key rotation) registers its issuer and public keys:

    pvesh set /cluster/secrets/k8s/<cluster> --issuer <iss> --jwks "$(cat jwks.json)"
    # or: pve-secrets k8s-register --cluster <cluster> --issuer <iss> --jwks jwks.json

- `<cluster>`: `a-z`, `0-9`, `-`, at most 40 characters.
- `--issuer`: the `iss` claim of the cluster's service-account tokens.
- `--jwks`: the cluster's `/openid/v1/jwks` document, or PEM public keys
  (RSA or EC P-256). Re-registering replaces the keys; publish a new key
  before the cluster signs with it.

`pvesh get /cluster/secrets/k8s` lists clusters; `pvesh delete
/cluster/secrets/k8s/<cluster>` removes the login (stored secrets stay).
Registration needs `Sys.Modify` on `/`.

## What a pod can read

| Login | Reads |
|---|---|
| `auth/k8s-<cluster>/login`, role `workload`, token `aud=openbao` | `secret/k8s/<cluster>/<namespace>/*` (KV v2) |

The namespace comes from the token (`kubernetes.io.namespace`), so a pod
reads only its own namespace's secrets. Tokens from the store last 1 hour.

## Consumers

External Secrets Operator (`ClusterSecretStore` with provider `vault`, auth
`jwt` using a service-account token with audience `openbao`, path
`k8s-<cluster>`, role `workload`, the Proxmox cluster CA) or the OpenBao CSI
provider. Packaging them as a pve-k8s add-on is done in pve-k8s.
