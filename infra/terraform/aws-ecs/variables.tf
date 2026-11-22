variable "region" {
  description = "AWS region."
  type        = string
}

variable "name" {
  description = "Name for the cluster, service, load balancer and roles."
  type        = string
  default     = "maple-proxy"
}

variable "image" {
  description = "The maple-proxy image (published on GitHub Container Registry; or your own copy, such as an ECR pull-through cache)."
  type        = string
  default     = "ghcr.io/kinncj/maple-proxy"
}

variable "image_tag" {
  description = "The release to run, such as 3.0.0. Pin one: never latest."
  type        = string
  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+(-[0-9A-Za-z.]+)?$", var.image_tag))
    error_message = "image_tag must be a release version such as 3.0.0."
  }
}

variable "replicas" {
  description = "How many proxies run behind the load balancer."
  type        = number
  default     = 2
}

variable "cpu" {
  description = "Fargate CPU units per task."
  type        = number
  default     = 512
}

variable "memory" {
  description = "Fargate memory per task, in MiB."
  type        = number
  default     = 1024
}

variable "cpu_architecture" {
  description = "X86_64 or ARM64 (the image has both)."
  type        = string
  default     = "ARM64"
}

variable "vpc_id" {
  description = "The VPC the proxy runs in, with a route to PostgreSQL, Redis and the providers."
  type        = string
}

variable "subnet_ids" {
  description = "Private subnets for the tasks and the internal load balancer."
  type        = list(string)
}

variable "allowed_cidrs" {
  description = "Networks allowed to reach the proxy's ports (your VPC's range, say). No default: nothing is open by accident."
  type        = list(string)
}

variable "allowed_hosts" {
  description = "Other host names clients use to reach the proxy (a DNS name in front of the load balancer)."
  type        = list(string)
  default     = []
}

variable "proxy_tokens_secret_arn" {
  description = "Secrets Manager ARN of the access tokens: one label=token per line."
  type        = string
}

variable "postgres_dsn_secret_arn" {
  description = "Secrets Manager ARN of the PostgreSQL DSN (postgres://user:password@host:5432/db?sslmode=require)."
  type        = string
}

variable "redis_url_secret_arn" {
  description = "Secrets Manager ARN of the Redis URL (rediss://:password@host:6379/0)."
  type        = string
}

variable "storage_key_secret_arn" {
  description = "Secrets Manager ARN of the storage key: 64 hex characters (openssl rand -hex 32)."
  type        = string
}

variable "extra_secret_arns" {
  description = "More secrets, as MAPLE_SECRET_<NAME> = ARN; a provider key: MAPLE_SECRET_PROVIDER_<ID>_API_KEY."
  type        = map(string)
  default     = {}
}
