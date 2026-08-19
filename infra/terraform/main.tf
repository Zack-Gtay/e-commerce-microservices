terraform {
  required_version = ">= 1.9.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.70"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }

  # Remote state with locking. Bucket and table are bootstrapped out-of-band (they cannot
  # live in the state they store). Supply the rest with:
  #   terraform init -backend-config=backend.hcl
  backend "s3" {
    key          = "eshop/terraform.tfstate"
    encrypt      = true
    use_lockfile = true
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project
      Environment = var.environment
      ManagedBy   = "terraform"
      Repository  = "Zack-Gtay/e-commerce-microservices"
    }
  }
}

data "aws_caller_identity" "current" {}

data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  name = "${var.project}-${var.environment}"

  account_id = data.aws_caller_identity.current.account_id
  azs        = slice(data.aws_availability_zones.available.names, 0, var.az_count)

  # Single source of truth for the service topology. Every ECR repo, log group, task
  # definition, ECS service and Cloud Map entry is generated from this map, so adding a
  # seventh microservice is one entry here rather than edits across five files.
  services = {
    catalog-api = {
      port          = 8080
      cpu           = 512
      memory        = 1024
      desired_count = 2
      public        = false
      health_path   = "/health"
    }
    basket-api = {
      port          = 8080
      cpu           = 512
      memory        = 1024
      desired_count = 2
      public        = false
      health_path   = "/health"
    }
    discount-grpc = {
      port          = 8080
      cpu           = 256
      memory        = 512
      desired_count = 2
      public        = false
      health_path   = "/"
    }
    ordering-api = {
      port          = 8080
      cpu           = 512
      memory        = 1024
      desired_count = 2
      public        = false
      health_path   = "/health"
    }
    yarp-api-gateway = {
      port          = 8080
      cpu           = 512
      memory        = 1024
      desired_count = 2
      public        = true
      health_path   = "/"
    }
    shopping-web = {
      port          = 8080
      cpu           = 512
      memory        = 1024
      desired_count = 2
      public        = true
      health_path   = "/"
    }
  }

  # Only these two are reachable from the internet through the ALB. Catalog, Basket,
  # Ordering and Discount stay on private subnets and are addressed through Cloud Map.
  public_services = { for k, v in local.services : k => v if v.public }
}
