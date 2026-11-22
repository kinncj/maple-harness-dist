# Terraform examples

maple-proxy on three managed container services, each in **central mode**: one or more proxies sharing a
PostgreSQL and a Redis you already run, so any instance can stop or move without losing anything. They are
examples to copy and adapt, not modules with a support promise.

| Folder | Service | Reached from | Surfaces |
| --- | --- | --- | --- |
| `aws-ecs/` | ECS on Fargate, behind an internal Network Load Balancer | your VPC | OpenAI (11535) and Anthropic (11537) |
| `gcp-cloud-run/` | Cloud Run, image through an Artifact Registry remote repository | your VPC (or the internet with `public = true`) | one per service: OpenAI, or Anthropic with `anthropic_surface = true` |
| `azure-container-apps/` | Container Apps in an internal environment | your virtual network | one per app: OpenAI, or Anthropic with `anthropic_surface = true` |

What they have in common:

- **No secret goes through Terraform.** Create the secrets in the cloud's secret manager first and pass their
  ARN, name or ID; the service gives them to the proxy at start as `MAPLE_SECRET_<NAME>` variables, the variable
  form of `${secret:...}`. They never appear in the Terraform state.
- **Four secrets are needed:** the access tokens (one `label=token` per line, the tokens your tools use with `mh_`
  in front), the PostgreSQL DSN, the Redis URL, and the storage key (64 hex characters). A provider key is one more:
  `MAPLE_SECRET_PROVIDER_<ID>_API_KEY`, referenced in `config.yaml` as `${secret:provider/<id>/api_key}`.
- **A pinned release.** `image_tag` is a version such as `3.0.0`; `latest` is refused. The image is
  `docker.io/kinncj/maple-harness:proxy-3.0.0` on Docker Hub (the `proxy-` is added for you on a repository named
  `maple-harness`; your own build in another repository keeps plain version tags). Cloud Run pulls it through an
  Artifact Registry remote repository in front of Docker Hub.
- **Private by default.** Nothing listens on the internet unless you change it, and the proxy answers only to the
  host names in `allowed_hosts` (Cloud Run and Container Apps: the service's own name, shown after the first apply,
  then apply again).
- **Settings in PostgreSQL**, starting from the defaults. Load a `config.yaml` of yours with
  `maple-proxy storage import-config --from config.yaml --force`, run anywhere that can reach the same PostgreSQL
  with the same storage key, or change them on a replica's setup page (loopback only, so through the service's
  own command access).

Making the secrets, for example on AWS:

```sh
printf 'laptop=%s\n' "$(openssl rand -hex 24)" > proxy_tokens
aws secretsmanager create-secret --name maple/proxy_tokens --secret-string file://proxy_tokens
aws secretsmanager create-secret --name maple/storage_key --secret-string "$(openssl rand -hex 32)"
aws secretsmanager create-secret --name maple/postgres_dsn --secret-string 'postgres://maple:...@db.example.internal:5432/maple?sslmode=require'
aws secretsmanager create-secret --name maple/redis_url --secret-string 'rediss://:...@cache.example.internal:6379/0'
```

then `terraform init`, and `terraform apply` with the variables in a `terraform.tfvars` of yours.

Behind the service's load balancer, many clients can reach the proxy from the same address, so one client's
wrong tokens can slow down the others. When the balancer adds `X-Forwarded-For`, set `MAPLE_TRUSTED_PROXIES` to
the balancer's own addresses only (see the Kubernetes page, Load balancing); the examples leave it unset.

Limits worth knowing: Fargate stops a task at most 120 seconds after asking it to, and Cloud Run 10 seconds after,
so a long stream can be cut when an instance is replaced (the examples set `MAPLE_SHUTDOWN_GRACE` to fit). The
Apple on-device model is macOS only, and the MCP hub belongs on a host or a Kubernetes pod of its own.

These examples were checked with `terraform validate`; they have not been applied to a real account.
