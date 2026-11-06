# The 6 APIs (apis.json) as Container Apps; their ingress is the front door (see outputs.tf).

locals {
  apis = { for a in jsondecode(file("${path.module}/../../apis.json")) : a.name => a }
  db   = data.terraform_remote_state.db.outputs
}

data "terraform_remote_state" "db" {
  backend = "local"
  config = {
    path = "${path.module}/../10-databases/terraform.tfstate"
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
  cloud    = "azure"
  api_name = each.key
}

resource "azurerm_resource_group" "apis" {
  name     = "rg-cloud-apis"
  location = "eastus"
}

resource "azurerm_container_app_environment" "apis" {
  name                = "cae-cloud-apis"
  location            = azurerm_resource_group.apis.location
  resource_group_name = azurerm_resource_group.apis.name
}

resource "azurerm_container_app" "api" {
  for_each                     = local.apis
  name                         = each.key
  container_app_environment_id = azurerm_container_app_environment.apis.id
  resource_group_name          = azurerm_resource_group.apis.name
  revision_mode                = "Single"

  secret {
    name  = "db-password"
    value = var.db_devuser_password
  }

  template {
    min_replicas = 1
    max_replicas = 1

    container {
      name   = "api"
      image  = "${each.key}:1.0"
      cpu    = 0.5
      memory = "1Gi"

      dynamic "env" {
        for_each = toset([for k in nonsensitive(keys(module.api_env[each.key].env)) : k if !contains(module.api_env[each.key].secret_names, k)])
        content {
          name  = env.value
          value = module.api_env[each.key].env[env.value]
        }
      }

      dynamic "env" {
        for_each = toset(module.api_env[each.key].secret_names)
        content {
          name        = env.value
          secret_name = "db-password"
        }
      }
    }
  }

  ingress {
    external_enabled = true
    target_port      = 8080
    traffic_weight {
      latest_revision = true
      percentage      = 100
    }
  }

  # floci-az does not return secret values on read, which would show as drift on every plan.
  lifecycle {
    ignore_changes = [secret]
  }
}
