# Messaging backbone.
#
# Two things live here:
#
#   1. Amazon MQ for RabbitMQ -- the like-for-like target for the code as it ships today.
#      BuildingBlocks.Messaging/MassTransit/Extentions.cs calls UsingRabbitMq, so this is
#      what MessageBroker__Host points at with no code change at all.
#
#   2. SQS + SNS with a dead-letter queue -- the AWS-native target state. Switching to it
#      is a one-line change in that same extension method (UsingRabbitMq -> UsingAmazonSqs),
#      which is exactly why the transport was centralised there.
#
# The SQS resources are created either way: they cost nothing idle, and they give the
# redrive/retry semantics the RabbitMQ setup currently lacks.

# ---------------------------------------------------------------------------
# Amazon MQ (RabbitMQ engine)
# ---------------------------------------------------------------------------

resource "random_password" "mq" {
  count = var.enable_amazon_mq ? 1 : 0

  length      = 32
  special     = false
  min_upper   = 1
  min_lower   = 1
  min_numeric = 1
}

resource "aws_mq_broker" "this" {
  count = var.enable_amazon_mq ? 1 : 0

  broker_name        = local.name
  engine_type        = "RabbitMQ"
  engine_version     = "3.13"
  host_instance_type = var.mq_instance_type

  # SINGLE_INSTANCE in staging; a clustered deployment in production.
  deployment_mode = var.environment == "production" ? "CLUSTER_MULTI_AZ" : "SINGLE_INSTANCE"

  subnet_ids      = var.environment == "production" ? [for s in aws_subnet.private : s.id] : [values(aws_subnet.private)[0].id]
  security_groups = [aws_security_group.data.id]

  publicly_accessible        = false
  auto_minor_version_upgrade = true

  user {
    username = "eshop"
    password = random_password.mq[0].result
  }

  logs {
    general = true
  }

  tags = { Name = local.name }
}

# ---------------------------------------------------------------------------
# SQS -- the checkout queue, with a real dead-letter policy
# ---------------------------------------------------------------------------

resource "aws_sqs_queue" "basket_checkout_dlq" {
  name = "${local.name}-basket-checkout-dlq"

  message_retention_seconds = 1209600 # 14 days, the maximum -- gives time to investigate
  sqs_managed_sse_enabled   = true

  tags = { Name = "${local.name}-basket-checkout-dlq" }
}

resource "aws_sqs_queue" "basket_checkout" {
  # Mirrors the kebab-case endpoint name MassTransit derives from BasketCheckoutEvent via
  # SetKebabCaseEndpointNameFormatter().
  name = "${local.name}-basket-checkout-event"

  # Long polling: fewer empty receives, lower cost, lower latency than short polling.
  receive_wait_time_seconds = 20

  # Must exceed the consumer's worst-case handling time, otherwise a slow BasketCheckout
  # handler gets its message redelivered while it is still working -- duplicate orders.
  visibility_timeout_seconds = 60

  message_retention_seconds = 345600 # 4 days
  sqs_managed_sse_enabled   = true

  # This is the piece the current RabbitMQ setup has no equivalent for: five attempts,
  # then the message is parked rather than lost or retried forever.
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.basket_checkout_dlq.arn
    maxReceiveCount     = 5
  })

  tags = { Name = "${local.name}-basket-checkout-event" }
}

resource "aws_sqs_queue_redrive_allow_policy" "basket_checkout_dlq" {
  queue_url = aws_sqs_queue.basket_checkout_dlq.id

  redrive_allow_policy = jsonencode({
    redrivePermission = "byQueue"
    sourceQueueArns   = [aws_sqs_queue.basket_checkout.arn]
  })
}

# ---------------------------------------------------------------------------
# SNS -- fan-out for integration events
# ---------------------------------------------------------------------------

resource "aws_sns_topic" "integration_events" {
  name = "${local.name}-integration-events"

  tags = { Name = "${local.name}-integration-events" }
}

resource "aws_sns_topic_subscription" "basket_checkout" {
  topic_arn = aws_sns_topic.integration_events.arn
  protocol  = "sqs"
  endpoint  = aws_sqs_queue.basket_checkout.arn

  # Ordering only cares about checkout events, not everything on the topic. Filtering at
  # the topic means the consumer is not woken up to discard messages it does not want.
  filter_policy = jsonencode({
    MessageType = ["BasketCheckoutEvent"]
  })
}

data "aws_iam_policy_document" "sqs_from_sns" {
  statement {
    effect    = "Allow"
    actions   = ["sqs:SendMessage"]
    resources = [aws_sqs_queue.basket_checkout.arn]

    principals {
      type        = "Service"
      identifiers = ["sns.amazonaws.com"]
    }

    condition {
      test     = "ArnEquals"
      variable = "aws:SourceArn"
      values   = [aws_sns_topic.integration_events.arn]
    }
  }
}

resource "aws_sqs_queue_policy" "basket_checkout" {
  queue_url = aws_sqs_queue.basket_checkout.id
  policy    = data.aws_iam_policy_document.sqs_from_sns.json
}
