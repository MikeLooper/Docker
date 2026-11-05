# Terraform owns the servers. The loader owns the databases and logins (D9).

resource "azurerm_resource_group" "data" {
  name     = "rg-cloud-data"
  location = "eastus"
}

resource "azurerm_mssql_server" "mssql" {
  name                         = "cloud-mssql"
  resource_group_name          = azurerm_resource_group.data.name
  location                     = azurerm_resource_group.data.location
  version                      = "12.0"
  administrator_login          = var.db_admin_user
  administrator_login_password = var.db_admin_password
}

resource "azurerm_mssql_firewall_rule" "allow_all" {
  name             = "allow-all"
  server_id        = azurerm_mssql_server.mssql.id
  start_ip_address = "0.0.0.0"
  end_ip_address   = "255.255.255.255"
}

resource "azurerm_postgresql_flexible_server" "postgres" {
  name                          = "cloud-postgres"
  resource_group_name           = azurerm_resource_group.data.name
  location                      = azurerm_resource_group.data.location
  version                       = "16"
  sku_name                      = "B_Standard_B1ms"
  storage_mb                    = 32768
  administrator_login           = var.db_admin_user
  administrator_password        = var.db_admin_password
  public_network_access_enabled = true

  # floci-az does not echo the zone back, which would show as drift on every plan.
  lifecycle {
    ignore_changes = [zone]
  }
}

resource "azurerm_postgresql_flexible_server_firewall_rule" "allow_all" {
  name             = "allow-all"
  server_id        = azurerm_postgresql_flexible_server.postgres.id
  start_ip_address = "0.0.0.0"
  end_ip_address   = "255.255.255.255"
}

# ARM omits the data-plane port, so the emulator's /connect API is read instead.
# The servers' containers join pilot-net, and /connect returns their container name and port.
data "http" "mssql_connect" {
  url        = "https://localhost:4577/devstoreaccount1-sql/servers/${azurerm_mssql_server.mssql.name}/connect"
  depends_on = [azurerm_mssql_server.mssql]

  lifecycle {
    postcondition {
      condition     = self.status_code == 200
      error_message = "The floci-az SQL /connect API did not answer 200."
    }
  }
}

data "http" "postgres_connect" {
  url        = "https://localhost:4577/devstoreaccount1-postgres/flexibleServers/${azurerm_postgresql_flexible_server.postgres.name}/connect"
  depends_on = [azurerm_postgresql_flexible_server.postgres]

  lifecycle {
    postcondition {
      condition     = self.status_code == 200
      error_message = "The floci-az PostgreSQL /connect API did not answer 200."
    }
  }
}

locals {
  # The /connect bodies also hold the admin password; only host and port are exposed.
  mssql_connect    = jsondecode(data.http.mssql_connect.response_body)
  postgres_connect = jsondecode(data.http.postgres_connect.response_body)
}
