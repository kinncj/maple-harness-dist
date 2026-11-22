# maple-proxy on Google Cloud Run, central mode: instances sharing a PostgreSQL and a Redis you
# already run (Cloud SQL, Memorystore), reached through your VPC. An EXAMPLE to copy and adapt.
#
# No secret value goes through Terraform: create the secrets in Secret Manager first and pass their
# names (see README.md). Cloud Run reads them at start; they never appear in the state.
#
# Cloud Run serves one port per service: this one serves the OpenAI-compatible surface. Clients that
# need the Anthropic-compatible surface use a second service with anthropic_surface = true.

terraform {
  required_version = ">= 1.6"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 7.0"
    }
  }
}

provider "google" {
  project = var.project
  region  = var.region
}

locals {
  port = var.anthropic_surface ? 11537 : 11535
  # Cloud Run pulls from Artifact Registry: a remote repository in front of Docker Hub, where the
  # proxy's release 3.0.0 is kinncj/maple-harness:proxy-3.0.0.
  image = "${var.region}-docker.pkg.dev/${var.project}/${google_artifact_registry_repository.dockerhub.repository_id}/kinncj/maple-harness:proxy-${var.image_tag}"
  # Each secret becomes MAPLE_SECRET_<NAME>, the variable form of ${secret:...}.
  secrets = merge({
    MAPLE_SECRET_ACCESS_PROXY_TOKENS  = var.proxy_tokens_secret
    MAPLE_SECRET_STORAGE_POSTGRES_DSN = var.postgres_dsn_secret
    MAPLE_SECRET_STORAGE_REDIS_URL    = var.redis_url_secret
    MAPLE_SECRET_STORAGE_KEY          = var.storage_key_secret
  }, var.extra_secrets)
}

resource "google_artifact_registry_repository" "dockerhub" {
  repository_id = "${var.name}-dockerhub"
  location      = var.region
  format        = "DOCKER"
  mode          = "REMOTE_REPOSITORY"
  description   = "Docker Hub, for the maple-proxy image"
  remote_repository_config {
    docker_repository {
      public_repository = "DOCKER_HUB"
    }
  }
}

# The identity the proxy runs as: it reads the listed secrets, nothing else. Give it your providers'
# roles (Vertex AI User, for a provider with no stored key) yourself.
resource "google_service_account" "proxy" {
  account_id   = var.name
  display_name = "maple-proxy"
}

resource "google_secret_manager_secret_iam_member" "proxy" {
  for_each  = local.secrets
  secret_id = each.value
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.proxy.email}"
}

resource "google_cloud_run_v2_service" "proxy" {
  name     = var.name
  location = var.region
  # Internal by default: reachable from your VPC only. A public address needs HTTPS (Cloud Run gives
  # it) and the proxy's tokens; set public = true for that.
  ingress             = var.public ? "INGRESS_TRAFFIC_ALL" : "INGRESS_TRAFFIC_INTERNAL_ONLY"
  deletion_protection = false

  template {
    service_account = google_service_account.proxy.email
    # Long enough for a running stream to finish.
    timeout = "3600s"

    scaling {
      min_instance_count = var.min_instances
      max_instance_count = var.max_instances
    }

    vpc_access {
      network_interfaces {
        network    = var.network
        subnetwork = var.subnetwork
      }
      egress = "PRIVATE_RANGES_ONLY"
    }

    containers {
      image = local.image
      args  = ["serve"]

      ports {
        container_port = local.port
      }

      resources {
        limits = {
          cpu    = "1"
          memory = "1Gi"
        }
        # The proxy keeps working between requests (usage, settings checks): always allocate CPU.
        cpu_idle = false
      }

      env {
        name  = "MAPLE_STORAGE_MODE"
        value = "central"
      }
      env {
        name  = "MAPLE_SETTINGS_SOURCE"
        value = "central"
      }
      env {
        name  = "MAPLE_READY_REQUIRES_SAME_CONFIG"
        value = "true"
      }
      env {
        name  = "MAPLE_PROXY_ID"
        value = var.name
      }
      env {
        # The service's run.app name (known after the first apply) or your domain: required.
        name  = "MAPLE_ALLOWED_HOSTS"
        value = join(",", var.allowed_hosts)
      }
      env {
        name  = "MAPLE_POSTGRES_DSN"
        value = "$${secret:storage/postgres_dsn}"
      }
      env {
        name  = "MAPLE_REDIS_URL"
        value = "$${secret:storage/redis_url}"
      }
      env {
        name  = "MAPLE_STORAGE_KEY"
        value = "$${secret:storage/key}"
      }
      env {
        # Cloud Run gives 10 seconds after SIGTERM.
        name  = "MAPLE_SHUTDOWN_GRACE"
        value = "8s"
      }

      dynamic "env" {
        for_each = local.secrets
        content {
          name = env.key
          value_source {
            secret_key_ref {
              secret  = env.value
              version = "latest"
            }
          }
        }
      }

      startup_probe {
        http_get {
          path = "/healthz"
          port = local.port
        }
        period_seconds    = 2
        failure_threshold = 30
      }
      liveness_probe {
        http_get {
          path = "/healthz"
          port = local.port
        }
        period_seconds = 10
      }
    }
  }

  depends_on = [google_secret_manager_secret_iam_member.proxy]
}

# Cloud Run's own sign-in would take the Authorization header the proxy's tokens travel in, so the
# service lets every caller through to the proxy, which refuses any request without a valid token.
# With ingress internal only, that is every caller inside your VPC.
resource "google_cloud_run_v2_service_iam_member" "invoker" {
  name     = google_cloud_run_v2_service.proxy.name
  location = var.region
  role     = "roles/run.invoker"
  member   = "allUsers"
}
