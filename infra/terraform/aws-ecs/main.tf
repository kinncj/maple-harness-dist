# maple-proxy on AWS ECS (Fargate), central mode: replicas behind an internal Network Load Balancer,
# sharing a PostgreSQL and a Redis you already run (RDS, ElastiCache). An EXAMPLE to copy and adapt.
#
# No secret value goes through Terraform: create the secrets in AWS Secrets Manager first and pass
# their ARNs (see README.md). The task reads them at start; they never appear in the state.

terraform {
  required_version = ">= 1.6"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region = var.region
}

locals {
  image = "${var.image}:${var.image_tag}"
  # Each secret becomes MAPLE_SECRET_<NAME>, the variable form of ${secret:...}: access/proxy_tokens
  # is MAPLE_SECRET_ACCESS_PROXY_TOKENS, storage/postgres_dsn is MAPLE_SECRET_STORAGE_POSTGRES_DSN.
  secrets = merge({
    MAPLE_SECRET_ACCESS_PROXY_TOKENS  = var.proxy_tokens_secret_arn
    MAPLE_SECRET_STORAGE_POSTGRES_DSN = var.postgres_dsn_secret_arn
    MAPLE_SECRET_STORAGE_REDIS_URL    = var.redis_url_secret_arn
    MAPLE_SECRET_STORAGE_KEY          = var.storage_key_secret_arn
  }, var.extra_secret_arns)
}

resource "aws_cloudwatch_log_group" "proxy" {
  name              = "/maple/${var.name}"
  retention_in_days = 30
}

resource "aws_ecs_cluster" "this" {
  name = var.name
}

# The execution role reads the listed secrets and writes logs; nothing else.
data "aws_iam_policy_document" "assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "execution" {
  name               = "${var.name}-execution"
  assume_role_policy = data.aws_iam_policy_document.assume.json
}

resource "aws_iam_role_policy_attachment" "execution" {
  role       = aws_iam_role.execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

data "aws_iam_policy_document" "secrets" {
  statement {
    actions   = ["secretsmanager:GetSecretValue"]
    resources = values(local.secrets)
  }
}

resource "aws_iam_role_policy" "secrets" {
  name   = "read-maple-secrets"
  role   = aws_iam_role.execution.id
  policy = data.aws_iam_policy_document.secrets.json
}

# The task role is what the proxy's own requests run as (Bedrock providers with no stored key, for
# example): attach your policies to it. It starts with none.
resource "aws_iam_role" "task" {
  name               = "${var.name}-task"
  assume_role_policy = data.aws_iam_policy_document.assume.json
}

resource "aws_security_group" "proxy" {
  name        = "${var.name}-proxy"
  description = "maple-proxy: the OpenAI and Anthropic ports from the allowed networks only"
  vpc_id      = var.vpc_id

  ingress {
    description = "OpenAI-compatible"
    from_port   = 11535
    to_port     = 11535
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidrs
  }
  ingress {
    description = "Anthropic-compatible"
    from_port   = 11537
    to_port     = 11537
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidrs
  }
  egress {
    description = "Providers, PostgreSQL, Redis"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_ecs_task_definition" "proxy" {
  family                   = var.name
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.cpu
  memory                   = var.memory
  execution_role_arn       = aws_iam_role.execution.arn
  task_role_arn            = aws_iam_role.task.arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = var.cpu_architecture
  }

  # The root file system is read-only; /data and /tmp are the task's own ephemeral storage. In
  # central mode nothing there needs to survive a restart.
  volume {
    name = "data"
  }
  volume {
    name = "tmp"
  }

  container_definitions = jsonencode([{
    name                   = "maple-proxy"
    image                  = local.image
    essential              = true
    command                = ["serve"]
    user                   = "65532:65532"
    readonlyRootFilesystem = true
    linuxParameters        = { capabilities = { drop = ["ALL"] }, initProcessEnabled = true }
    portMappings = [
      { name = "openai", containerPort = 11535, protocol = "tcp" },
      { name = "anthropic", containerPort = 11537, protocol = "tcp" },
    ]
    mountPoints = [
      { sourceVolume = "data", containerPath = "/data" },
      { sourceVolume = "tmp", containerPath = "/tmp" },
    ]
    environment = [
      { name = "MAPLE_STORAGE_MODE", value = "central" },
      { name = "MAPLE_SETTINGS_SOURCE", value = "central" },
      { name = "MAPLE_READY_REQUIRES_SAME_CONFIG", value = "true" },
      { name = "MAPLE_PROXY_ID", value = var.name },
      { name = "MAPLE_ALLOWED_HOSTS", value = join(",", concat([aws_lb.proxy.dns_name], var.allowed_hosts)) },
      # Fargate stops a task at most 120 seconds after SIGTERM: finish running requests before that.
      { name = "MAPLE_SHUTDOWN_GRACE", value = "100s" },
      { name = "MAPLE_POSTGRES_DSN", value = "$${secret:storage/postgres_dsn}" },
      { name = "MAPLE_REDIS_URL", value = "$${secret:storage/redis_url}" },
      { name = "MAPLE_STORAGE_KEY", value = "$${secret:storage/key}" },
      # Never fall back to the instance metadata when the task role is missing.
      { name = "AWS_EC2_METADATA_DISABLED", value = "true" },
    ]
    secrets     = [for k, v in local.secrets : { name = k, valueFrom = v }]
    stopTimeout = 120
    healthCheck = {
      command     = ["CMD", "/usr/local/bin/maple-proxy", "healthcheck"]
      interval    = 15
      timeout     = 3
      retries     = 3
      startPeriod = 30
    }
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        awslogs-group         = aws_cloudwatch_log_group.proxy.name
        awslogs-region        = var.region
        awslogs-stream-prefix = "proxy"
      }
    }
  }])
}

# An internal Network Load Balancer: reachable from your VPC (and what it is peered with) only. Put
# HTTPS in front of it (an ALB with a certificate, or TLS on the NLB) for clients outside the VPC.
resource "aws_lb" "proxy" {
  name               = var.name
  internal           = true
  load_balancer_type = "network"
  subnets            = var.subnet_ids
  security_groups    = [aws_security_group.proxy.id]
}

resource "aws_lb_target_group" "proxy" {
  for_each    = { openai = 11535, anthropic = 11537 }
  name        = "${var.name}-${each.key}"
  port        = each.value
  protocol    = "TCP"
  target_type = "ip"
  vpc_id      = var.vpc_id
  # Long enough for a running stream to finish after the task leaves the balancer.
  deregistration_delay = 110

  health_check {
    protocol = "TCP"
    port     = "traffic-port"
  }
}

resource "aws_lb_listener" "proxy" {
  for_each          = aws_lb_target_group.proxy
  load_balancer_arn = aws_lb.proxy.arn
  port              = each.value.port
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = each.value.arn
  }
}

resource "aws_ecs_service" "proxy" {
  name            = var.name
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.proxy.arn
  desired_count   = var.replicas
  launch_type     = "FARGATE"

  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent         = 200

  network_configuration {
    subnets          = var.subnet_ids
    security_groups  = [aws_security_group.proxy.id]
    assign_public_ip = false
  }

  dynamic "load_balancer" {
    for_each = { openai = 11535, anthropic = 11537 }
    content {
      target_group_arn = aws_lb_target_group.proxy[load_balancer.key].arn
      container_name   = "maple-proxy"
      container_port   = load_balancer.value
    }
  }

  depends_on = [aws_lb_listener.proxy]
}
