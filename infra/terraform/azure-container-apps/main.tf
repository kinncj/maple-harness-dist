# maple-proxy on Azure Container Apps, central mode: replicas sharing a PostgreSQL and a Redis you
# already run (Azure Database for PostgreSQL, Azure Cache for Redis), in your virtual network. An
# EXAMPLE to copy and adapt.
#
# No secret value goes through Terraform: create the secrets in Key Vault first and pass their IDs
# (see README.md). The app reads them through its managed identity; they never appear in the state.
#
# Container Apps ingress serves one port: this app serves the OpenAI-compatible surface. Clients that
# need the Anthropic-compatible surface use a second app with anthropic_surface = true.

terraform {
  required_version = ">= 1.6"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}

provider "azurerm" {
  features {}
  subscription_id = var.subscription_id
}

locals {
  port = var.anthropic_surface ? 11537 : 11535
  # Container Apps secret names are lowercase with dashes; each is given to the proxy as
  # MAPLE_SECRET_<NAME>, the variable form of ${secret:...}.
  secrets = merge({
    "access-proxy-tokens"  = { env = "MAPLE_SECRET_ACCESS_PROXY_TOKENS", id = var.proxy_tokens_secret_id }
    "storage-postgres-dsn" = { env = "MAPLE_SECRET_STORAGE_POSTGRES_DSN", id = var.postgres_dsn_secret_id }
    "storage-redis-url"    = { env = "MAPLE_SECRET_STORAGE_REDIS_URL", id = var.redis_url_secret_id }
    "storage-key"          = { env = "MAPLE_SECRET_STORAGE_KEY", id = var.storage_key_secret_id }
  }, var.extra_secrets)
  env = {
    MAPLE_STORAGE_MODE               = "central"
    MAPLE_SETTINGS_SOURCE            = "central"
    MAPLE_READY_REQUIRES_SAME_CONFIG = "true"
    MAPLE_PROXY_ID                   = var.name
    # The app's own name (known after the first apply) or your domain: required.
    MAPLE_ALLOWED_HOSTS = join(",", var.allowed_hosts)
    MAPLE_POSTGRES_DSN  = "$${secret:storage/postgres_dsn}"
    MAPLE_REDIS_URL     = "$${secret:storage/redis_url}"
    MAPLE_STORAGE_KEY   = "$${secret:storage/key}"
  }
}

resource "azurerm_log_analytics_workspace" "this" {
  name                = var.name
  location            = var.location
  resource_group_name = var.resource_group_name
  sku                 = "PerGB2018"
  retention_in_days   = 30
}

resource "azurerm_container_app_environment" "this" {
  name                       = var.name
  location                   = var.location
  resource_group_name        = var.resource_group_name
  log_analytics_workspace_id = azurerm_log_analytics_workspace.this.id
  # A subnet of your virtual network (delegated to Microsoft.App/environments), with routes to
  # PostgreSQL and Redis. Internal: no public address unless you add one.
  infrastructure_subnet_id       = var.subnet_id
  internal_load_balancer_enabled = true
}

# The identity the app reads its Key Vault secrets with (the listed ones only). Give it your providers' roles (Cognitive
# Services OpenAI User, for an Azure provider with no stored key) yourself.
resource "azurerm_user_assigned_identity" "proxy" {
  name                = var.name
  location            = var.location
  resource_group_name = var.resource_group_name
}

# One assignment per secret, scoped to that secret alone: the app cannot read anything else in the
# vault. A versionless secret ID is https://<vault>.vault.azure.net/secrets/<name>.
resource "azurerm_role_assignment" "secrets" {
  for_each             = local.secrets
  scope                = "${var.key_vault_id}/secrets/${split("/", trimsuffix(each.value.id, "/"))[4]}"
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_user_assigned_identity.proxy.principal_id
}

resource "azurerm_container_app" "proxy" {
  name                         = var.name
  container_app_environment_id = azurerm_container_app_environment.this.id
  resource_group_name          = var.resource_group_name
  revision_mode                = "Single"

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.proxy.id]
  }

  dynamic "secret" {
    for_each = local.secrets
    content {
      name                = secret.key
      key_vault_secret_id = secret.value.id
      identity            = azurerm_user_assigned_identity.proxy.id
    }
  }

  ingress {
    # Reachable from other apps in this environment only. To reach it from the rest of the virtual
    # network, set external_enabled = true: the environment is internal, so that still has no public
    # address.
    external_enabled = false
    target_port      = local.port
    transport        = "http"
    traffic_weight {
      latest_revision = true
      percentage      = 100
    }
  }

  template {
    min_replicas = var.min_replicas
    max_replicas = var.max_replicas
    # Long enough for a running stream to finish after the replica stops taking new requests.
    termination_grace_period_seconds = 600

    container {
      name   = "maple-proxy"
      image  = "${var.image}:${var.image_tag}"
      args   = ["serve"]
      cpu    = 0.5
      memory = "1Gi"

      dynamic "env" {
        for_each = local.env
        content {
          name  = env.key
          value = env.value
        }
      }
      dynamic "env" {
        for_each = local.secrets
        content {
          name        = env.value.env
          secret_name = env.key
        }
      }

      startup_probe {
        transport               = "HTTP"
        path                    = "/healthz"
        port                    = local.port
        interval_seconds        = 2
        failure_count_threshold = 30
      }
      liveness_probe {
        transport        = "HTTP"
        path             = "/healthz"
        port             = local.port
        interval_seconds = 10
      }
      readiness_probe {
        transport        = "HTTP"
        path             = "/readyz"
        port             = local.port
        interval_seconds = 5
      }

      volume_mounts {
        name = "data"
        path = "/data"
      }
      volume_mounts {
        name = "tmp"
        path = "/tmp"
      }
    }

    # In central mode nothing under /data needs to survive a restart.
    volume {
      name         = "data"
      storage_type = "EmptyDir"
    }
    volume {
      name         = "tmp"
      storage_type = "EmptyDir"
    }
  }

  depends_on = [azurerm_role_assignment.secrets]
}
