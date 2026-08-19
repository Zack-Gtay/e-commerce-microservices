# Distributed cache behind CachedBasketRepository.
#
# Engine is Valkey rather than Redis OSS: it is the drop-in successor after the Redis
# licence change, is wire-compatible with StackExchange.Redis, and is cheaper per node on
# ElastiCache. No application change is required -- AddStackExchangeRedisCache in
# src/Services/Basket/Basket.API/Program.cs connects to it unmodified.

resource "aws_elasticache_replication_group" "cache" {
  replication_group_id = "${local.name}-cache"
  description          = "Basket distributed cache for ${local.name}"

  engine         = "valkey"
  engine_version = "7.2"
  node_type      = var.redis_node_type
  port           = 6379

  # A single node in staging; a replica per AZ with automatic failover in production.
  num_cache_clusters         = var.environment == "production" ? var.az_count : 1
  automatic_failover_enabled = var.environment == "production"
  multi_az_enabled           = var.environment == "production"

  subnet_group_name  = aws_elasticache_subnet_group.this.name
  security_group_ids = [aws_security_group.data.id]

  at_rest_encryption_enabled = true
  transit_encryption_enabled = false # StackExchange.Redis would need ssl=true in the connection string

  # Baskets are disposable: evict the coldest key rather than refusing writes when the
  # node fills up. This is the infrastructure-side compensation for the missing TTL on
  # SetStringAsync in CachedBasketRepository.
  parameter_group_name = aws_elasticache_parameter_group.cache.name

  snapshot_retention_limit = var.environment == "production" ? 5 : 0
  apply_immediately        = var.environment != "production"

  tags = { Name = "${local.name}-cache" }
}

resource "aws_elasticache_parameter_group" "cache" {
  name   = "${local.name}-cache"
  family = "valkey7"

  parameter {
    name  = "maxmemory-policy"
    value = "allkeys-lru"
  }
}
