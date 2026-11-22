variable "project" {
  description = "Google Cloud project ID."
  type        = string
}

variable "region" {
  description = "Region for the service and the Artifact Registry repository."
  type        = string
}

variable "name" {
  description = "Name for the service, its service account and the registry repository."
  type        = string
  default     = "maple-proxy"
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
  description = "Serve the Anthropic-compatible surface instead of the OpenAI-compatible one (Cloud Run serves one port)."
  type        = bool
  default     = false
}

variable "public" {
  description = "Accept requests from the internet (with HTTPS and the proxy's tokens), not only from your VPC."
  type        = bool
  default     = false
}

variable "allowed_hosts" {
  description = "Host names clients use: the service's run.app name (shown after the first apply) and your own domain."
  type        = list(string)
  validation {
    condition     = length(var.allowed_hosts) > 0
    error_message = "Name at least one host: the proxy answers only to host names it knows."
  }
}

variable "min_instances" {
  description = "Instances kept running."
  type        = number
  default     = 1
}

variable "max_instances" {
  description = "Most instances at once."
  type        = number
  default     = 3
}

variable "network" {
  description = "The VPC network with routes to PostgreSQL and Redis."
  type        = string
}

variable "subnetwork" {
  description = "The subnetwork Cloud Run sends private traffic through."
  type        = string
}

variable "proxy_tokens_secret" {
  description = "Secret Manager secret (name or ID) with the access tokens: one label=token per line."
  type        = string
}

variable "postgres_dsn_secret" {
  description = "Secret Manager secret with the PostgreSQL DSN (postgres://user:password@host:5432/db?sslmode=require)."
  type        = string
}

variable "redis_url_secret" {
  description = "Secret Manager secret with the Redis URL (rediss://:password@host:6378/0 for Memorystore with TLS)."
  type        = string
}

variable "storage_key_secret" {
  description = "Secret Manager secret with the storage key: 64 hex characters (openssl rand -hex 32)."
  type        = string
}

variable "extra_secrets" {
  description = "More secrets, as MAPLE_SECRET_<NAME> = secret; a provider key: MAPLE_SECRET_PROVIDER_<ID>_API_KEY."
  type        = map(string)
  default     = {}
}
