# Public ALB. Only the YARP gateway and the Razor Pages web app sit behind it; the four
# back-end services are private and reached through Cloud Map service discovery.

resource "aws_lb" "this" {
  name               = local.name
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = [for s in aws_subnet.public : s.id]

  drop_invalid_header_fields = true
  enable_deletion_protection = var.environment == "production"

  tags = { Name = local.name }
}

resource "aws_lb_target_group" "this" {
  for_each = local.public_services

  name        = substr("${local.name}-${each.key}", 0, 32)
  port        = each.value.port
  protocol    = "HTTP"
  vpc_id      = aws_vpc.this.id
  target_type = "ip" # required for Fargate awsvpc networking

  # Give a task 30s of grace before the first probe so EF Core migrations and Marten
  # schema creation can finish on cold start.
  health_check {
    enabled             = true
    path                = each.value.health_path
    matcher             = "200-399"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  deregistration_delay = 30

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"

  # Default to the web UI; the gateway is matched by rule below.
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.this["shopping-web"].arn
  }
}

# Everything under the gateway's route prefixes goes to YARP, which then strips the prefix
# and forwards to the private service -- mirroring the ReverseProxy config in
# src/ApiGateways/YarpApiGateway/appsettings.json.
resource "aws_lb_listener_rule" "gateway" {
  listener_arn = aws_lb_listener.http.arn
  priority     = 100

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.this["yarp-api-gateway"].arn
  }

  condition {
    path_pattern {
      values = [
        "/catalog-service/*",
        "/basket-service/*",
        "/ordering-service/*",
      ]
    }
  }
}
