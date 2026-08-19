variable "project" {
  description = "Short project slug used to prefix every resource name."
  type        = string
  default     = "eshop"
}

variable "environment" {
  description = "Deployment environment."
  type        = string
  default     = "staging"

  validation {
    condition     = contains(["staging", "production"], var.environment)
    error_message = "environment must be one of: staging, production."
  }
}

variable "aws_region" {
  description = "AWS region to deploy into."
  type        = string
  default     = "eu-west-1"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC."
  type        = string
  default     = "10.0.0.0/16"
}

variable "az_count" {
  description = "Number of availability zones to spread subnets across."
  type        = number
  default     = 2

  validation {
    condition     = var.az_count >= 2 && var.az_count <= 3
    error_message = "az_count must be 2 or 3 (two is the minimum for a highly available ALB)."
  }
}

variable "image_tag" {
  description = "Container image tag to run. Set to the commit SHA by the deploy workflow."
  type        = string
  default     = "latest"
}

variable "log_retention_days" {
  description = "CloudWatch Logs retention for service log groups."
  type        = number
  default     = 30
}

# ---------------------------------------------------------------------------
# Data stores
# ---------------------------------------------------------------------------

variable "postgres_instance_class" {
  description = "Instance class for the shared PostgreSQL server (Catalog + Basket document stores)."
  type        = string
  default     = "db.t4g.micro"
}

variable "sqlserver_instance_class" {
  description = "Instance class for the SQL Server instance backing Ordering."
  type        = string
  default     = "db.t3.small"
}

variable "redis_node_type" {
  description = "ElastiCache node type for the Basket distributed cache."
  type        = string
  default     = "cache.t4g.micro"
}

variable "enable_sqlserver" {
  description = <<-EOT
    Provision RDS for SQL Server for the Ordering service.
    Off by default because a SQL Server instance is expensive to leave running in a
    demo account; flip to true for an environment that actually serves traffic.
  EOT
  type        = bool
  default     = false
}

variable "enable_amazon_mq" {
  description = <<-EOT
    Provision Amazon MQ for RabbitMQ.
    True keeps the currently-shipped MassTransit RabbitMQ transport working unchanged.
    Set to false once BuildingBlocks.Messaging is switched to UsingAmazonSqs, at which
    point the SQS/SNS resources in sqs.tf become the messaging backbone.
  EOT
  type        = bool
  default     = true
}

variable "mq_instance_type" {
  description = "Amazon MQ broker instance type."
  type        = string
  default     = "mq.t3.micro"
}

# ---------------------------------------------------------------------------
# CI/CD federation
# ---------------------------------------------------------------------------

variable "github_repository" {
  description = "owner/repo allowed to assume the deployment role via GitHub OIDC."
  type        = string
  default     = "Zack-Gtay/e-commerce-microservices"
}

variable "create_github_oidc_provider" {
  description = <<-EOT
    Create the GitHub OIDC provider in this account.
    An AWS account can only have one provider per URL, so set this to false if another
    stack in the same account already created token.actions.githubusercontent.com.
  EOT
  type        = bool
  default     = true
}
