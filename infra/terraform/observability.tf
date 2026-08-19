# CloudWatch alarms and a dashboard.
#
# These are the operational half of "own the delivery pipeline end to end": the deploy is
# not finished when the task is running, it is finished when something is watching it.

resource "aws_sns_topic" "alarms" {
  name = "${local.name}-alarms"
}

# ---------------------------------------------------------------------------
# Per-service alarms
# ---------------------------------------------------------------------------

resource "aws_cloudwatch_metric_alarm" "cpu_high" {
  for_each = local.services

  alarm_name          = "${local.name}-${each.key}-cpu-high"
  alarm_description   = "${each.key} CPU above 85% for 10 minutes"
  namespace           = "AWS/ECS"
  metric_name         = "CPUUtilization"
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 2
  threshold           = 85
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    ClusterName = aws_ecs_cluster.this.name
    ServiceName = aws_ecs_service.this[each.key].name
  }

  alarm_actions = [aws_sns_topic.alarms.arn]
  ok_actions    = [aws_sns_topic.alarms.arn]
}

resource "aws_cloudwatch_metric_alarm" "running_tasks_low" {
  for_each = local.services

  alarm_name          = "${local.name}-${each.key}-no-running-tasks"
  alarm_description   = "${each.key} has fewer running tasks than desired"
  namespace           = "ECS/ContainerInsights"
  metric_name         = "RunningTaskCount"
  statistic           = "Minimum"
  period              = 60
  evaluation_periods  = 3
  threshold           = each.value.desired_count
  comparison_operator = "LessThanThreshold"
  treat_missing_data  = "breaching"

  dimensions = {
    ClusterName = aws_ecs_cluster.this.name
    ServiceName = aws_ecs_service.this[each.key].name
  }

  alarm_actions = [aws_sns_topic.alarms.arn]
}

# ---------------------------------------------------------------------------
# The alarm that actually matters for an event-driven system
# ---------------------------------------------------------------------------

resource "aws_cloudwatch_metric_alarm" "dlq_not_empty" {
  alarm_name          = "${local.name}-checkout-dlq-not-empty"
  alarm_description   = "A basket checkout event failed every retry and was dead-lettered. Each message here is a customer who checked out and never got an order."
  namespace           = "AWS/SQS"
  metric_name         = "ApproximateNumberOfMessagesVisible"
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 1
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    QueueName = aws_sqs_queue.basket_checkout_dlq.name
  }

  alarm_actions = [aws_sns_topic.alarms.arn]
}

resource "aws_cloudwatch_metric_alarm" "checkout_queue_backlog" {
  alarm_name          = "${local.name}-checkout-queue-age"
  alarm_description   = "Oldest unprocessed checkout is over 5 minutes old -- Ordering is not keeping up"
  namespace           = "AWS/SQS"
  metric_name         = "ApproximateAgeOfOldestMessage"
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 5
  threshold           = 300
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    QueueName = aws_sqs_queue.basket_checkout.name
  }

  alarm_actions = [aws_sns_topic.alarms.arn]
}

resource "aws_cloudwatch_metric_alarm" "alb_5xx" {
  alarm_name          = "${local.name}-alb-5xx"
  alarm_description   = "Elevated 5xx responses from the load balancer"
  namespace           = "AWS/ApplicationELB"
  metric_name         = "HTTPCode_Target_5XX_Count"
  statistic           = "Sum"
  period              = 60
  evaluation_periods  = 5
  threshold           = 10
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    LoadBalancer = aws_lb.this.arn_suffix
  }

  alarm_actions = [aws_sns_topic.alarms.arn]
}

resource "aws_cloudwatch_metric_alarm" "alb_latency" {
  alarm_name          = "${local.name}-alb-p99-latency"
  alarm_description   = "p99 response time above 2s"
  namespace           = "AWS/ApplicationELB"
  metric_name         = "TargetResponseTime"
  extended_statistic  = "p99"
  period              = 60
  evaluation_periods  = 5
  threshold           = 2
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    LoadBalancer = aws_lb.this.arn_suffix
  }

  alarm_actions = [aws_sns_topic.alarms.arn]
}

# ---------------------------------------------------------------------------
# Log-derived metric: the LoggingBehavior slow-request warning
# ---------------------------------------------------------------------------

resource "aws_cloudwatch_log_metric_filter" "slow_requests" {
  for_each = local.services

  name           = "${local.name}-${each.key}-slow-requests"
  log_group_name = aws_cloudwatch_log_group.this[each.key].name

  # Emitted by BuildingBlocks/Behaviors/LoggingBehavior.cs when a MediatR request takes
  # more than three seconds.
  #
  # The quotes are load-bearing: an unquoted [PERFORMANCE] is parsed by CloudWatch Logs
  # as a space-delimited field selector, not as literal text.
  pattern = "\"[PERFORMANCE]\""

  metric_transformation {
    name          = "SlowRequests"
    namespace     = "EShop/${title(var.environment)}"
    value         = "1"
    default_value = "0"
  }
}

resource "aws_cloudwatch_dashboard" "this" {
  dashboard_name = local.name

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 12
        height = 6
        properties = {
          title  = "ECS CPU by service"
          region = var.aws_region
          view   = "timeSeries"
          metrics = [
            for name in keys(local.services) :
            ["AWS/ECS", "CPUUtilization", "ClusterName", aws_ecs_cluster.this.name, "ServiceName", name]
          ]
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 0
        width  = 12
        height = 6
        properties = {
          title  = "Checkout queue depth and DLQ"
          region = var.aws_region
          view   = "timeSeries"
          metrics = [
            ["AWS/SQS", "ApproximateNumberOfMessagesVisible", "QueueName", aws_sqs_queue.basket_checkout.name],
            ["AWS/SQS", "ApproximateNumberOfMessagesVisible", "QueueName", aws_sqs_queue.basket_checkout_dlq.name],
          ]
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 6
        width  = 24
        height = 6
        properties = {
          title  = "ALB requests and errors"
          region = var.aws_region
          view   = "timeSeries"
          metrics = [
            ["AWS/ApplicationELB", "RequestCount", "LoadBalancer", aws_lb.this.arn_suffix],
            ["AWS/ApplicationELB", "HTTPCode_Target_5XX_Count", "LoadBalancer", aws_lb.this.arn_suffix],
            ["AWS/ApplicationELB", "TargetResponseTime", "LoadBalancer", aws_lb.this.arn_suffix],
          ]
        }
      }
    ]
  })
}
