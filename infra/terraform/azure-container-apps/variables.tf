variable "subscription_id" {
  description = "Azure subscription ID."
  type        = string
}

variable "resource_group_name" {
  description = "An existing resource group."
  type        = string
}

variable "location" {
  description = "Azure region."
  type        = string
}

variable "name" {
  description = "Name for the environment, app, identity and log workspace."
  type        = string
  default     = "maple-proxy"
}

variable "image" {
  description = "The maple-proxy image, on Docker Hub (its tags are proxy-<release>)."
  type        = string
  default     = "docker.io/kinncj/maple-harness"
}

variable "image_tag" {
  description = "The release to run, such as 3.0.0. Pin one: never latest."
  type        = string
  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+(-[0-9A-Za-z.]+)?$", var.image_tag))
    error_message = "image_tag must be a release version such as 3.0.0."
  }
}

variable "anthropic_surface" {
  description = "Serve the Anthropic-compatible surface instead of the OpenAI-compatible one (ingress serves one port)."
  type        = bool
  default     = false
}

variable "allowed_hosts" {
  description = "Host names clients use: the app's name in the environment (shown after the first apply) and your own domain."
  type        = list(string)
  validation {
    condition     = length(var.allowed_hosts) > 0
    error_message = "Name at least one host: the proxy answers only to host names it knows."
  }
}

variable "min_replicas" {
  description = "Replicas kept running."
  type        = number
  default     = 1
}

variable "max_replicas" {
  description = "Most replicas at once."
  type        = number
  default     = 3
}

variable "subnet_id" {
  description = "A subnet delegated to Microsoft.App/environments, with routes to PostgreSQL and Redis."
  type        = string
}

variable "key_vault_id" {
  description = "The Key Vault (RBAC permission model) that holds the secrets below."
  type        = string
}

variable "proxy_tokens_secret_id" {
  description = "Key Vault secret ID, versionless (https://<vault>.vault.azure.net/secrets/<name>), of the access tokens: one label=token per line."
  type        = string
  validation {
    condition     = can(regex("^https://[^/]+\\.vault\\.(azure\\.net|azure\\.cn|usgovcloudapi\\.net)/secrets/[^/]+/?$", var.proxy_tokens_secret_id))
    error_message = "A versionless Key Vault secret ID: https://<vault>.vault.azure.net/secrets/<name>."
  }
}

variable "postgres_dsn_secret_id" {
  description = "Key Vault secret ID of the PostgreSQL DSN (postgres://user:password@host:5432/db?sslmode=require)."
  type        = string
  validation {
    condition     = can(regex("^https://[^/]+\\.vault\\.(azure\\.net|azure\\.cn|usgovcloudapi\\.net)/secrets/[^/]+/?$", var.postgres_dsn_secret_id))
    error_message = "A versionless Key Vault secret ID: https://<vault>.vault.azure.net/secrets/<name>."
  }
}

variable "redis_url_secret_id" {
  description = "Key Vault secret ID of the Redis URL (rediss://:password@host:6380/0)."
  type        = string
  validation {
    condition     = can(regex("^https://[^/]+\\.vault\\.(azure\\.net|azure\\.cn|usgovcloudapi\\.net)/secrets/[^/]+/?$", var.redis_url_secret_id))
    error_message = "A versionless Key Vault secret ID: https://<vault>.vault.azure.net/secrets/<name>."
  }
}

variable "storage_key_secret_id" {
  description = "Key Vault secret ID of the storage key: 64 hex characters (openssl rand -hex 32)."
  type        = string
  validation {
    condition     = can(regex("^https://[^/]+\\.vault\\.(azure\\.net|azure\\.cn|usgovcloudapi\\.net)/secrets/[^/]+/?$", var.storage_key_secret_id))
    error_message = "A versionless Key Vault secret ID: https://<vault>.vault.azure.net/secrets/<name>."
  }
}

variable "extra_secrets" {
  description = "More secrets: Container Apps secret name => { env = \"MAPLE_SECRET_<NAME>\", id = Key Vault secret ID }."
  type        = map(object({ env = string, id = string }))
  default     = {}
}
