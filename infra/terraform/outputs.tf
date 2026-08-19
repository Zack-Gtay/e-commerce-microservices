output "alb_dns_name" {
  description = "Public entry point. Set this as the GATEWAY_BASE_URL environment variable in GitHub so deploy.yml can smoke-test it."
  value       = "http://${aws_lb.this.dns_name}"
}

output "github_actions_role_arn" {
  description = "Store as the AWS_GHA_ROLE_ARN GitHub secret. Not a credential -- it is only usable from the trusted repository."
  value       = aws_iam_role.github_actions.arn
}

output "ecr_repository_urls" {
  description = "One repository per service."
  value       = { for k, r in aws_ecr_repository.this : k => r.repository_url }
}

output "ecs_cluster_name" {
  description = "Cluster the deploy workflow targets."
  value       = aws_ecs_cluster.this.name
}

output "service_discovery_namespace" {
  description = "Private DNS namespace used for east-west calls (e.g. discount-grpc.eshop.local)."
  value       = aws_service_discovery_private_dns_namespace.this.name
}

output "postgres_endpoint" {
  description = "Shared PostgreSQL endpoint backing the Catalog and Basket Marten stores."
  value       = aws_db_instance.postgres.endpoint
}

output "redis_endpoint" {
  description = "Valkey primary endpoint used by CachedBasketRepository."
  value       = aws_elasticache_replication_group.cache.primary_endpoint_address
}

output "checkout_queue_url" {
  description = "SQS queue that receives BasketCheckoutEvent."
  value       = aws_sqs_queue.basket_checkout.url
}

output "checkout_dlq_url" {
  description = "Dead-letter queue. A non-zero depth here means checkouts were dropped."
  value       = aws_sqs_queue.basket_checkout_dlq.url
}

output "alarm_topic_arn" {
  description = "Subscribe email/PagerDuty/Slack to this to actually receive the alarms."
  value       = aws_sns_topic.alarms.arn
}

output "secret_arns" {
  description = "Secrets Manager entries injected into task definitions."
  value       = { for k, s in aws_secretsmanager_secret.this : k => s.arn }
}
