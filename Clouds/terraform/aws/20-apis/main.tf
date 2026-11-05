# The 6 APIs (apis.json) on ECS Fargate, each behind its own API Gateway HTTP API (v2).

locals {
  apis        = { for a in jsondecode(file("${path.module}/../../apis.json")) : a.name => a }
  registry    = "000000000000.dkr.ecr.us-east-1.amazonaws.com"
  db          = data.terraform_remote_state.db.outputs
  invoke_base = "http://%s.execute-api.localhost.floci.io:4566"
}

data "terraform_remote_state" "db" {
  backend = "local"
  config = {
    path = "${path.module}/../10-databases/terraform.tfstate"
  }
}

resource "aws_security_group" "api" {
  name   = "cloud-api"
  vpc_id = local.db.vpc_id

  ingress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

module "api_env" {
  source   = "../../modules/api-env"
  for_each = local.apis

  lang     = each.value.lang
  db       = each.value.db
  host     = each.value.db == "mssql" ? local.db.mssql_host : local.db.postgres_host
  port     = each.value.db == "mssql" ? local.db.mssql_port : local.db.postgres_port
  password = var.db_devuser_password
  cloud    = "aws"
  api_name = each.key
}

resource "aws_ecr_repository" "api" {
  for_each             = local.apis
  name                 = each.key
  force_delete         = true
  image_tag_mutability = "MUTABLE"
}

resource "aws_ecs_cluster" "apis" {
  name = "cloud-apis"
}

resource "aws_iam_role" "task_execution" {
  name = "cloud-api-task-execution"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_cloudwatch_log_group" "api" {
  for_each          = local.apis
  name              = "/ecs/${each.key}"
  retention_in_days = 7
}

resource "aws_service_discovery_private_dns_namespace" "cloud" {
  name = "cloud.local"
  vpc  = local.db.vpc_id
}

resource "aws_service_discovery_service" "api" {
  for_each = local.apis
  name     = each.key

  dns_config {
    namespace_id = aws_service_discovery_private_dns_namespace.cloud.id
    dns_records {
      ttl  = 10
      type = "A"
    }
    routing_policy = "MULTIVALUE"
  }
}

resource "aws_ecs_task_definition" "api" {
  for_each                 = local.apis
  family                   = each.key
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "512"
  memory                   = "1024"
  execution_role_arn       = aws_iam_role.task_execution.arn

  container_definitions = jsonencode([{
    name         = "api"
    image        = "${local.registry}/${each.key}:1.0"
    essential    = true
    portMappings = [{ containerPort = 8080, protocol = "tcp" }]
    environment  = [for k in sort(keys(module.api_env[each.key].env)) : { name = k, value = module.api_env[each.key].env[k] }]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.api[each.key].name
        "awslogs-region"        = "us-east-1"
        "awslogs-stream-prefix" = "api"
      }
    }
  }])

  depends_on = [aws_ecr_repository.api]
}

resource "aws_ecs_service" "api" {
  for_each        = local.apis
  name            = each.key
  cluster         = aws_ecs_cluster.apis.id
  task_definition = aws_ecs_task_definition.api[each.key].arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = local.db.subnet_ids
    security_groups  = [aws_security_group.api.id]
    assign_public_ip = false
  }

  service_registries {
    registry_arn   = aws_service_discovery_service.api[each.key].arn
    container_name = "api"
    container_port = 8080
  }
}

resource "aws_apigatewayv2_vpc_link" "apis" {
  name               = "cloud-apis"
  subnet_ids         = local.db.subnet_ids
  security_group_ids = [aws_security_group.api.id]
}

resource "aws_apigatewayv2_api" "api" {
  for_each      = local.apis
  name          = each.key
  protocol_type = "HTTP"
}

resource "aws_apigatewayv2_integration" "api" {
  for_each           = local.apis
  api_id             = aws_apigatewayv2_api.api[each.key].id
  integration_type   = "HTTP_PROXY"
  integration_method = "ANY"
  connection_type    = "VPC_LINK"
  connection_id      = aws_apigatewayv2_vpc_link.apis.id
  integration_uri    = aws_service_discovery_service.api[each.key].arn
}

resource "aws_apigatewayv2_route" "proxy" {
  for_each  = local.apis
  api_id    = aws_apigatewayv2_api.api[each.key].id
  route_key = "ANY /{proxy+}"
  target    = "integrations/${aws_apigatewayv2_integration.api[each.key].id}"
}

resource "aws_apigatewayv2_stage" "default" {
  for_each    = local.apis
  api_id      = aws_apigatewayv2_api.api[each.key].id
  name        = "$default"
  auto_deploy = true
}
