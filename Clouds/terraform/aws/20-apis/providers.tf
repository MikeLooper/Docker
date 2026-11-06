# Floci (local-aws). Terraform runs inside local-aws's network namespace, so localhost:4566 is the emulator.
provider "aws" {
  region                      = "us-east-1"
  access_key                  = "test"
  secret_key                  = "test"
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true

  endpoints {
    apigatewayv2     = "http://localhost:4566"
    ec2              = "http://localhost:4566"
    ecr              = "http://localhost:4566"
    ecs              = "http://localhost:4566"
    iam              = "http://localhost:4566"
    logs             = "http://localhost:4566"
    servicediscovery = "http://localhost:4566"
    sts              = "http://localhost:4566"
  }
}
