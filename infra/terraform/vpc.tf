# Two-tier VPC: public subnets carry only the ALB and the NAT gateways; every ECS task,
# database and cache lives on a private subnet with no inbound route from the internet.

resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true # required for Cloud Map private DNS and RDS endpoints

  tags = { Name = local.name }
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id
  tags   = { Name = local.name }
}

resource "aws_subnet" "public" {
  for_each = { for idx, az in local.azs : az => idx }

  vpc_id                  = aws_vpc.this.id
  availability_zone       = each.key
  cidr_block              = cidrsubnet(var.vpc_cidr, 4, each.value)
  map_public_ip_on_launch = true

  tags = {
    Name = "${local.name}-public-${each.key}"
    Tier = "public"
  }
}

resource "aws_subnet" "private" {
  for_each = { for idx, az in local.azs : az => idx }

  vpc_id            = aws_vpc.this.id
  availability_zone = each.key
  cidr_block        = cidrsubnet(var.vpc_cidr, 4, each.value + var.az_count)

  tags = {
    Name = "${local.name}-private-${each.key}"
    Tier = "private"
  }
}

# One NAT gateway per AZ. Costs more than a single shared NAT, but a NAT outage then
# takes out one AZ instead of every private subnet in the VPC.
resource "aws_eip" "nat" {
  for_each = aws_subnet.public

  domain = "vpc"
  tags   = { Name = "${local.name}-nat-${each.key}" }
}

resource "aws_nat_gateway" "this" {
  for_each = aws_subnet.public

  allocation_id = aws_eip.nat[each.key].id
  subnet_id     = each.value.id

  tags       = { Name = "${local.name}-${each.key}" }
  depends_on = [aws_internet_gateway.this]
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }

  tags = { Name = "${local.name}-public" }
}

resource "aws_route_table_association" "public" {
  for_each = aws_subnet.public

  subnet_id      = each.value.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table" "private" {
  for_each = aws_subnet.private

  vpc_id = aws_vpc.this.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.this[each.key].id
  }

  tags = { Name = "${local.name}-private-${each.key}" }
}

resource "aws_route_table_association" "private" {
  for_each = aws_subnet.private

  subnet_id      = each.value.id
  route_table_id = aws_route_table.private[each.key].id
}

# ---------------------------------------------------------------------------
# Security groups -- one per tier, referencing each other by id rather than CIDR
# ---------------------------------------------------------------------------

resource "aws_security_group" "alb" {
  name        = "${local.name}-alb"
  description = "Public entry point"
  vpc_id      = aws_vpc.this.id

  ingress {
    description = "HTTP from the internet"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS from the internet"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${local.name}-alb" }
}

resource "aws_security_group" "tasks" {
  name        = "${local.name}-tasks"
  description = "ECS Fargate tasks"
  vpc_id      = aws_vpc.this.id

  ingress {
    description     = "Traffic from the ALB"
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  ingress {
    description = "East-west traffic between services (Basket -> Discount gRPC, gateway -> APIs)"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    self        = true
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${local.name}-tasks" }
}

resource "aws_security_group" "data" {
  name        = "${local.name}-data"
  description = "Databases, cache and broker. Reachable only from ECS tasks."
  vpc_id      = aws_vpc.this.id

  ingress {
    description     = "PostgreSQL"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.tasks.id]
  }

  ingress {
    description     = "SQL Server"
    from_port       = 1433
    to_port         = 1433
    protocol        = "tcp"
    security_groups = [aws_security_group.tasks.id]
  }

  ingress {
    description     = "Redis"
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    security_groups = [aws_security_group.tasks.id]
  }

  ingress {
    description     = "AMQP over TLS (Amazon MQ)"
    from_port       = 5671
    to_port         = 5671
    protocol        = "tcp"
    security_groups = [aws_security_group.tasks.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${local.name}-data" }
}

resource "aws_db_subnet_group" "this" {
  name       = local.name
  subnet_ids = [for s in aws_subnet.private : s.id]
  tags       = { Name = local.name }
}

resource "aws_elasticache_subnet_group" "this" {
  name       = local.name
  subnet_ids = [for s in aws_subnet.private : s.id]
}
