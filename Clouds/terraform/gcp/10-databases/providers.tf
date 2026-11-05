# floci-gcp (local-gcp). Terraform runs inside local-gcp's network namespace, so
# localhost:4588 is the emulator. No real credentials are needed.
provider "google" {
  project                          = "floci-local"
  region                           = "us-central1"
  zone                             = "us-central1-a"
  access_token                     = "floci"
  user_project_override            = false
  compute_custom_endpoint          = "http://localhost:4588/compute/v1/"
  sql_custom_endpoint              = "http://localhost:4588/"
  cloud_run_v2_custom_endpoint     = "http://localhost:4588/v2/"
  service_usage_custom_endpoint    = "http://localhost:4588/v1/"
  resource_manager_custom_endpoint = "http://localhost:4588/v1/"
  iam_custom_endpoint              = "http://localhost:4588/v1/"
}
