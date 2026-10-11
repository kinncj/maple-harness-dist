# Maple Harness: container and Kubernetes samples

Samples for running maple-proxy in a container, alone or as several replicas. They are starting
points to copy and adapt, not a supported product: read them, change them, and run them with your
own registry, secrets and databases.

| Path | What it is |
| --- | --- |
| `docker/Dockerfile` | Builds the image from a published release (checksums and signature checked); nothing is compiled. |
| `docker/compose.yaml` | One proxy, its state on one volume. |
| `docker/compose.ha.yaml` | Three proxies, PostgreSQL, Redis and a load balancer (Caddy), for trying the shared mode. |
| `manifest/maple-proxy/` | The proxy's Deployment, Service, PodDisruptionBudget, example ConfigMap and Secret. |
| `manifest/postgres/`, `manifest/redis/` | Single-instance samples for trying it out. Use your managed services in production. |
| `manifest/maple-mcp-hub/` | The MCP hub as its own single replica. |
| `manifest/maple-lake/` | Usage history in a DuckLake: an hourly copy and a daily maintenance job (official DuckDB image). |
| `config/single/` | One replica, disk mode, its state on a PersistentVolumeClaim. |
| `config/ha/` | Three replicas, central mode (PostgreSQL and Redis), settings from the ConfigMap. |
| `config/ha-lake/` | `config/ha` plus the DuckLake jobs. |

Build the image first (no image is published):

```sh
cd docker
docker buildx build --build-arg MAPLE_VERSION=v2.0.0 \
  --platform linux/amd64,linux/arm64 -t registry.example.com/you/maple-proxy:2.0.0 --push .
```

Then, for Kubernetes:

```sh
cd config/single        # or config/ha
kustomize edit set image maple-proxy=registry.example.com/you/maple-proxy:2.0.0
# edit the Secret (manifest/maple-proxy/secret.example.yaml, and config/ha's patch) first
kubectl apply -k .
```

The documentation walks through both: the Docker and Kubernetes pages of the Maple Harness
documentation site.

The proxy binary inside the image is the released one: free to use, closed source, no warranty
(see the licence in the image under /usr/share/maple-harness). The images these samples pull
(debian, distroless, PostgreSQL, Redis, Caddy) have their own licences.
