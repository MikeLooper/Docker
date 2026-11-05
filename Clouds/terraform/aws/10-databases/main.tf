# Terraform owns the servers. The loader owns the databases and logins (D9).

resource "aws_vpc" "cloud" {
  cidr_block = "10.42.0.0/16"
  tags       = { Name = "cloud-vpc" }
}

resource "aws_subnet" "a" {
  vpc_id            = aws_vpc.cloud.id
  cidr_block        = "10.42.1.0/24"
  availability_zone = "us-east-1a"
  tags              = { Name = "cloud-subnet-a" }

  # After a local-aws restart, Floci can leave the old ECS task ENIs behind, and they
  # block subnet deletion. Fail fast; the builder's -destroy then forgets the network.
  timeouts {
    delete = "2m"
  }
}

resource "aws_subnet" "b" {
  vpc_id            = aws_vpc.cloud.id
  cidr_block        = "10.42.2.0/24"
  availability_zone = "us-east-1b"
  tags              = { Name = "cloud-subnet-b" }

  # After a local-aws restart, Floci can leave the old ECS task ENIs behind, and they
  # block subnet deletion. Fail fast; the builder's -destroy then forgets the network.
  timeouts {
    delete = "2m"
  }
}

resource "aws_db_subnet_group" "cloud" {
  name       = "cloud-db-subnets"
  subnet_ids = [aws_subnet.a.id, aws_subnet.b.id]
}

resource "aws_security_group" "db" {
  name   = "cloud-db"
  vpc_id = aws_vpc.cloud.id

  ingress {
    from_port   = 1433
    to_port     = 1433
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.cloud.cidr_block]
  }

  ingress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.cloud.cidr_block]
  }
}

resource "aws_db_instance" "mssql" {
  identifier             = "cloud-mssql"
  engine                 = "sqlserver-se"
  license_model          = "license-included"
  instance_class         = "db.m5.large"
  allocated_storage      = 20
  username               = var.db_admin_user
  password               = var.db_admin_password
  port                   = 7001
  db_subnet_group_name   = aws_db_subnet_group.cloud.name
  vpc_security_group_ids = [aws_security_group.db.id]
  skip_final_snapshot    = true
  apply_immediately      = true

  # Floci does not echo license_model back, which would show as drift on every plan.
  lifecycle {
    ignore_changes = [license_model]
  }
}

resource "aws_db_instance" "postgres" {
  identifier             = "cloud-postgres"
  engine                 = "postgres"
  engine_version         = "17"
  instance_class         = "db.t3.micro"
  allocated_storage      = 20
  username               = var.db_admin_user
  password               = var.db_admin_password
  port                   = 7002
  db_subnet_group_name   = aws_db_subnet_group.cloud.name
  vpc_security_group_ids = [aws_security_group.db.id]
  skip_final_snapshot    = true
  apply_immediately      = true
}
