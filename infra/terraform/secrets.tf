# Every connection string the services need, stored in Secrets Manager and injected into
# the task definition by ARN. This is what replaces the plaintext credentials currently
# committed in appsettings.json and docker-compose.override.yml.

locals {
  # Marten needs a Npgsql connection string, not the raw RDS endpoint.
  postgres_host = aws_db_instance.postgres.address

  secret_values = merge(
    {
      "catalog-db" = "Server=${local.postgres_host};Port=5432;Database=CatalogDb;User Id=${aws_db_instance.postgres.username};Password=${random_password.postgres.result};SSL Mode=Require;Trust Server Certificate=true"
      "basket-db"  = "Server=${local.postgres_host};Port=5432;Database=BasketDb;User Id=${aws_db_instance.postgres.username};Password=${random_password.postgres.result};SSL Mode=Require;Trust Server Certificate=true"
      "redis"      = "${aws_elasticache_replication_group.cache.primary_endpoint_address}:6379"

      "broker-host"     = var.enable_amazon_mq ? aws_mq_broker.this[0].instances[0].endpoints[0] : "amqp://localhost:5672"
      "broker-user"     = "eshop"
      "broker-password" = var.enable_amazon_mq ? random_password.mq[0].result : "unused"
    },
    var.enable_sqlserver ? {
      "ordering-db" = "Server=${aws_db_instance.sqlserver[0].address},1433;Database=OrderDb;User Id=${aws_db_instance.sqlserver[0].username};Password=${random_password.sqlserver[0].result};Encrypt=True;TrustServerCertificate=True"
    } : {}
  )
}

resource "aws_secretsmanager_secret" "this" {
  for_each = local.secret_values

  name        = "${local.name}/${each.key}"
  description = "Connection secret '${each.key}' for ${local.name}"

  # Staging is torn down and rebuilt often; the default 30-day window would block
  # recreating a secret with the same name.
  recovery_window_in_days = var.environment == "production" ? 30 : 0
}

resource "aws_secretsmanager_secret_version" "this" {
  for_each = local.secret_values

  secret_id     = aws_secretsmanager_secret.this[each.key].id
  secret_string = each.value
}
