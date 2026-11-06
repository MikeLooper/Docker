# floci-az (local-azure). Terraform runs inside local-azure's network namespace, so
# localhost:4577 is the emulator and matches the TLS certificate's localhost SAN.
# SSL_CERT_FILE (set by the builder) points at the system bundle plus the floci-az CA.
provider "azurerm" {
  features {
    api_management {
      # floci-az has no soft-delete endpoints; purging on destroy would fail.
      purge_soft_delete_on_destroy = false
      recover_soft_deleted         = false
    }
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }
  use_cli                         = false
  environment                     = "stack"
  metadata_host                   = "localhost:4577"
  subscription_id                 = "00000000-0000-0000-0000-000000000001"
  tenant_id                       = "00000000-0000-0000-0000-000000000002"
  client_id                       = "11111111-1111-1111-1111-111111111111"
  client_secret                   = "floci-az-dev-secret"
  resource_provider_registrations = "none"
}
