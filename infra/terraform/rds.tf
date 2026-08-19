# PostgreSQL backs both Marten document stores (Catalog and Basket). One instance, two
# logical databases -- they stay logically isolated per service, which is the property
# that matters, without paying for two instances in a staging environment.
#
# For production you would split these into separate instances so a noisy Catalog cannot
# starve Basket of connections.

resource "random_password" "postgres" {
  length  = 32
  special = false # RDS rejects several punctuation characters in master passwords
}

resource "aws_db_instance" "postgres" {
  identifier     = "${local.name}-postgres"
  engine         = "postgres"
  engine_version = "16.4"
  instance_class = var.postgres_instance_class

  allocated_storage     = 20
  max_allocated_storage = 100
  storage_type          = "gp3"
  storage_encrypted     = true

  db_name  = "CatalogDb"
  username = "eshop_admin"
  password = random_password.postgres.result
  port     = 5432

  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [aws_security_group.data.id]
  publicly_accessible    = false

  multi_az                = var.environment == "production"
  backup_retention_period = var.environment == "production" ? 14 : 1
  deletion_protection     = var.environment == "production"
  skip_final_snapshot     = var.environment != "production"

  performance_insights_enabled    = true
  enabled_cloudwatch_logs_exports = ["postgresql"]

  auto_minor_version_upgrade = true
  apply_immediately          = var.environment != "production"

  tags = { Name = "${local.name}-postgres" }
}

# ---------------------------------------------------------------------------
# SQL Server for Ordering (EF Core relational model)
# ---------------------------------------------------------------------------

resource "random_password" "sqlserver" {
  count = var.enable_sqlserver ? 1 : 0

  length  = 32
  special = false
}

resource "aws_db_instance" "sqlserver" {
  count = var.enable_sqlserver ? 1 : 0

  identifier     = "${local.name}-sqlserver"
  engine         = "sqlserver-ex"
  engine_version = "16.00.4165.4.v1"
  instance_class = var.sqlserver_instance_class
  license_model  = "license-included"

  allocated_storage = 20
  storage_type      = "gp3"
  storage_encrypted = true

  username = "eshop_admin"
  password = random_password.sqlserver[0].result
  port     = 1433

  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [aws_security_group.data.id]
  publicly_accessible    = false

  backup_retention_period = var.environment == "production" ? 14 : 1
  deletion_protection     = var.environment == "production"
  skip_final_snapshot     = var.environment != "production"

  tags = { Name = "${local.name}-sqlserver" }
}
