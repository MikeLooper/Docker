# The 6 APIs (apis.json) as Cloud Run services. The service URL is the front door
# (floci-gcp has no API Gateway / Apigee / Cloud Endpoints).

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
  cloud    = "gcp"
  api_name = each.key
}

resource "google_cloud_run_v2_service" "api" {
  for_each            = local.apis
  name                = each.key
  location            = "us-central1"
  deletion_protection = false
  ingress             = "INGRESS_TRAFFIC_ALL"

  template {
    scaling {
      min_instance_count = 1
      max_instance_count = 1
    }

    containers {
      image = "${each.key}:1.0"

      ports {
        container_port = 8080
      }

      resources {
        limits = {
          cpu    = "1"
          memory = "1Gi"
        }
      }

      # Cloud Run secrets are not emulated, so the DB password is a plain env var (dev only).
      dynamic "env" {
        for_each = toset(nonsensitive(keys(module.api_env[each.key].env)))
        content {
          name  = env.value
          value = module.api_env[each.key].env[env.value]
        }
      }
    }
  }
}

resource "google_cloud_run_v2_service_iam_member" "public" {
  for_each = local.apis
  name     = google_cloud_run_v2_service.api[each.key].name
  location = google_cloud_run_v2_service.api[each.key].location
  role     = "roles/run.invoker"
  member   = "allUsers"
}
