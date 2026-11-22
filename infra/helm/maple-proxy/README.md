# maple-proxy Helm chart

maple-proxy on Kubernetes, the same setups as the Kustomize samples in `../../config`:

| Values | Kustomize sample | What runs |
| --- | --- | --- |
| `mode: disk` (the default) | `config/single` | One replica, everything it keeps on a PersistentVolumeClaim; settings edited on the setup page. |
| `mode: central`, `settings.source: central` | `config/ha-shared` (recommended for several replicas) | Several replicas sharing PostgreSQL and Redis; settings kept in PostgreSQL, `config` copied in once. |
| `mode: central`, `settings.source: file` | `config/ha` | The same, with `config` as the settings every replica runs (read-only on the setup page). |
| `mode: redis` | `config/ha-redis` | Several replicas sharing one durable Redis and no PostgreSQL; settings kept in Redis (or `settings.source: file`). Each replica keeps a small claim of its own; `redis.enabled` runs the durable sample Redis (append-only file, `noeviction`, a claim). |
| `lake.enabled: true` | `config/ha-lake` | Adds the hourly and daily usage lake jobs. |
| `mcpHub.enabled: true` | `manifest/maple-mcp-hub` | Adds the MCP hub as its own single replica, with its own Secret. |
| `metrics.serviceMonitor.enabled: true` | `config/metrics` | A ServiceMonitor for the Prometheus Operator. |
| `serviceAccount.annotations` | `config/cloud-identity/*` | Workload identity on EKS, GKE or AKS. |

The chart never holds a secret: tokens, passwords, DSNs and the storage key live in Secrets you create, named
by `existingSecret` (and `postgres.existingSecret`, `redis.existingSecret`, `mcpHub.existingSecret`,
`lake.existingSecret`). An install without them stops with the reason. The `values.yaml` file lists every
setting with what it does.

```sh
kubectl create namespace maple
printf 'laptop=%s\n' "$(openssl rand -hex 24)" > proxy_tokens
kubectl -n maple create secret generic maple-proxy --from-file=access.proxy_tokens=./proxy_tokens
helm install maple-proxy oci://ghcr.io/kinncj/charts/maple-proxy --version 3.0.0 \
  -n maple --set existingSecret=maple-proxy
```

The `ci/` folder holds the values the chart is checked with. The Kubernetes page of the documentation walks through
every setup, upgrades and backups.
