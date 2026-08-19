# ECS Fargate cluster, one service per microservice, wired together with Cloud Map.

resource "aws_ecs_cluster" "this" {
  name = local.name

  setting {
    name  = "containerInsights"
    value = "enabled" # feeds CloudWatch Container Insights dashboards
  }
}

resource "aws_ecs_cluster_capacity_providers" "this" {
  cluster_name       = aws_ecs_cluster.this.name
  capacity_providers = ["FARGATE", "FARGATE_SPOT"]

  default_capacity_provider_strategy {
    capacity_provider = "FARGATE"
    weight            = 1
    base              = 1
  }
}

# ---------------------------------------------------------------------------
# Service discovery
#
# Gives every task a stable private DNS name (e.g. discount-grpc.eshop.local), which is
# what replaces the Docker Compose service names the code uses locally.
# ---------------------------------------------------------------------------

resource "aws_service_discovery_private_dns_namespace" "this" {
  name        = "${var.project}.local"
  description = "Internal service discovery for ${local.name}"
  vpc         = aws_vpc.this.id
}

resource "aws_service_discovery_service" "this" {
  for_each = local.services

  name = each.key

  dns_config {
    namespace_id = aws_service_discovery_private_dns_namespace.this.id

    dns_records {
      ttl  = 10
      type = "A"
    }

    routing_policy = "MULTIVALUE"
  }

  health_check_custom_config {
    failure_threshold = 1
  }
}

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------

resource "aws_cloudwatch_log_group" "this" {
  for_each = local.services

  name              = "/ecs/${local.name}/${each.key}"
  retention_in_days = var.log_retention_days
}

# ---------------------------------------------------------------------------
# IAM
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "ecs_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

# Used by the ECS agent: pull images, write logs, resolve secrets.
resource "aws_iam_role" "execution" {
  name               = "${local.name}-task-execution"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume.json
}

resource "aws_iam_role_policy_attachment" "execution_managed" {
  role       = aws_iam_role.execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

data "aws_iam_policy_document" "execution_secrets" {
  statement {
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [for s in aws_secretsmanager_secret.this : s.arn]
  }
}

resource "aws_iam_role_policy" "execution_secrets" {
  name   = "read-connection-secrets"
  role   = aws_iam_role.execution.id
  policy = data.aws_iam_policy_document.execution_secrets.json
}

# Used by the application code itself.
resource "aws_iam_role" "task" {
  name               = "${local.name}-task"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume.json
}

data "aws_iam_policy_document" "task" {
  # Least privilege: the app may work its own queues and topic, nothing else.
  statement {
    actions = [
      "sqs:SendMessage",
      "sqs:ReceiveMessage",
      "sqs:DeleteMessage",
      "sqs:GetQueueUrl",
      "sqs:GetQueueAttributes",
      "sqs:ChangeMessageVisibility",
    ]
    resources = [
      aws_sqs_queue.basket_checkout.arn,
      aws_sqs_queue.basket_checkout_dlq.arn,
    ]
  }

  statement {
    actions   = ["sns:Publish", "sns:Subscribe"]
    resources = [aws_sns_topic.integration_events.arn]
  }

  statement {
    actions   = ["cloudwatch:PutMetricData"]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "task" {
  name   = "app-permissions"
  role   = aws_iam_role.task.id
  policy = data.aws_iam_policy_document.task.json
}

# ---------------------------------------------------------------------------
# Task definitions
# ---------------------------------------------------------------------------

locals {
  registry = "${local.account_id}.dkr.ecr.${var.aws_region}.amazonaws.com"

  # Base configuration every container receives.
  common_env = [
    { name = "ASPNETCORE_ENVIRONMENT", value = title(var.environment) },
    { name = "ASPNETCORE_HTTP_PORTS", value = "8080" },
    { name = "DOTNET_gcServer", value = "1" },
  ]

  # Per-service configuration. Mirrors the environment blocks in
  # src/docker-compose.override.yml, with Compose service names swapped for Cloud Map DNS.
  service_env = {
    catalog-api = []

    basket-api = [
      { name = "GrpcSettings__DiscountUrl", value = "http://discount-grpc.${var.project}.local:8080" },
    ]

    discount-grpc = [
      { name = "ConnectionStrings__Database", value = "Data Source=/tmp/discountdb" },
    ]

    ordering-api = [
      { name = "FeatureManagement__OrderFullfilment", value = "false" },
    ]

    yarp-api-gateway = [
      { name = "ReverseProxy__Clusters__catalog-cluster__Destinations__destination1__Address", value = "http://catalog-api.${var.project}.local:8080" },
      { name = "ReverseProxy__Clusters__basket-cluster__Destinations__destination1__Address", value = "http://basket-api.${var.project}.local:8080" },
      { name = "ReverseProxy__Clusters__ordering-cluster__Destinations__destination1__Address", value = "http://ordering-api.${var.project}.local:8080" },
    ]

    shopping-web = [
      { name = "ApiSettings__GatewayAddress", value = "http://yarp-api-gateway.${var.project}.local:8080" },
    ]
  }

  # Secrets are injected by ARN and never appear in the task definition body -- this is
  # what replaces the plaintext connection strings currently sitting in appsettings.json.
  service_secrets = {
    catalog-api = [
      { name = "ConnectionStrings__Database", valueFrom = aws_secretsmanager_secret.this["catalog-db"].arn },
    ]
    basket-api = [
      { name = "ConnectionStrings__Database", valueFrom = aws_secretsmanager_secret.this["basket-db"].arn },
      { name = "ConnectionStrings__Redis", valueFrom = aws_secretsmanager_secret.this["redis"].arn },
      { name = "MessageBroker__Host", valueFrom = aws_secretsmanager_secret.this["broker-host"].arn },
      { name = "MessageBroker__UserName", valueFrom = aws_secretsmanager_secret.this["broker-user"].arn },
      { name = "MessageBroker__Password", valueFrom = aws_secretsmanager_secret.this["broker-password"].arn },
    ]
    discount-grpc = []
    ordering-api = concat(
      var.enable_sqlserver ? [{ name = "ConnectionStrings__Database", valueFrom = aws_secretsmanager_secret.this["ordering-db"].arn }] : [],
      [
        { name = "MessageBroker__Host", valueFrom = aws_secretsmanager_secret.this["broker-host"].arn },
        { name = "MessageBroker__UserName", valueFrom = aws_secretsmanager_secret.this["broker-user"].arn },
        { name = "MessageBroker__Password", valueFrom = aws_secretsmanager_secret.this["broker-password"].arn },
      ]
    )
    yarp-api-gateway = []
    shopping-web     = []
  }
}

resource "aws_ecs_task_definition" "this" {
  for_each = local.services

  family                   = each.key
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = each.value.cpu
  memory                   = each.value.memory
  execution_role_arn       = aws_iam_role.execution.arn
  task_role_arn            = aws_iam_role.task.arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }

  container_definitions = jsonencode([
    {
      name      = each.key
      image     = "${local.registry}/eshop/${each.key}:${var.image_tag}"
      essential = true

      portMappings = [{
        containerPort = each.value.port
        protocol      = "tcp"
      }]

      environment = concat(local.common_env, lookup(local.service_env, each.key, []))
      secrets     = lookup(local.service_secrets, each.key, [])

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.this[each.key].name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "ecs"
        }
      }

      # Container-level probe against the service's own /health endpoint (the one wired
      # up by AddHealthChecks + UseHealthChecks in each Program.cs). ECS replaces a task
      # that fails this even when the ALB is not routing to it.
      healthCheck = {
        command     = ["CMD-SHELL", "curl -fsS http://localhost:${each.value.port}${each.value.health_path} || exit 1"]
        interval    = 30
        timeout     = 5
        retries     = 3
        startPeriod = 60
      }
    }
  ])
}

# ---------------------------------------------------------------------------
# Services
# ---------------------------------------------------------------------------

resource "aws_ecs_service" "this" {
  for_each = local.services

  name            = each.key
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.this[each.key].arn
  desired_count   = each.value.desired_count
  launch_type     = "FARGATE"

  # Rolling deploy that keeps capacity up, then rolls itself back if the new tasks never
  # reach a healthy state. This is what makes `wait-for-service-stability` in deploy.yml
  # a real gate rather than a timer.
  deployment_maximum_percent         = 200
  deployment_minimum_healthy_percent = 100

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  network_configuration {
    subnets          = [for s in aws_subnet.private : s.id]
    security_groups  = [aws_security_group.tasks.id]
    assign_public_ip = false
  }

  service_registries {
    registry_arn = aws_service_discovery_service.this[each.key].arn
  }

  dynamic "load_balancer" {
    for_each = each.value.public ? [1] : []

    content {
      target_group_arn = aws_lb_target_group.this[each.key].arn
      container_name   = each.key
      container_port   = each.value.port
    }
  }

  health_check_grace_period_seconds = each.value.public ? 60 : null

  lifecycle {
    # The deploy workflow is the source of truth for which image is running, so Terraform
    # must not revert the task definition on the next plan.
    ignore_changes = [task_definition, desired_count]
  }

  depends_on = [aws_lb_listener.http]
}

# ---------------------------------------------------------------------------
# Autoscaling -- CPU target tracking
# ---------------------------------------------------------------------------

resource "aws_appautoscaling_target" "this" {
  for_each = local.services

  service_namespace  = "ecs"
  resource_id        = "service/${aws_ecs_cluster.this.name}/${aws_ecs_service.this[each.key].name}"
  scalable_dimension = "ecs:service:DesiredCount"
  min_capacity       = each.value.desired_count
  max_capacity       = each.value.desired_count * 5
}

resource "aws_appautoscaling_policy" "cpu" {
  for_each = local.services

  name               = "${each.key}-cpu-target"
  policy_type        = "TargetTrackingScaling"
  service_namespace  = aws_appautoscaling_target.this[each.key].service_namespace
  resource_id        = aws_appautoscaling_target.this[each.key].resource_id
  scalable_dimension = aws_appautoscaling_target.this[each.key].scalable_dimension

  target_tracking_scaling_policy_configuration {
    target_value       = 65
    scale_in_cooldown  = 300
    scale_out_cooldown = 60

    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
  }
}
