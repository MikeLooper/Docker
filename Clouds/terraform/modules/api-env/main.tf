# Builds the container environment for one cloud-api-* image.
# The images carry no DB or security settings (D7); everything is injected here.

terraform {
  required_version = ">= 1.5"
}

variable "lang" {
  description = "dotnet | java | python"
  type        = string
  validation {
    condition     = contains(["dotnet", "java", "python"], var.lang)
    error_message = "lang must be dotnet, java or python."
  }
}

variable "db" {
  description = "mssql | postgres"
  type        = string
  validation {
    condition     = contains(["mssql", "postgres"], var.db)
    error_message = "db must be mssql or postgres."
  }
}

variable "host" {
  type = string
}

variable "port" {
  type = number
}

variable "user" {
  type    = string
  default = "DevUser"
}

variable "password" {
  type      = string
  sensitive = true
}

variable "cloud" {
  description = "aws | azure | gcp | local (Phase 0 test)"
  type        = string
}

variable "api_name" {
  type = string
}

variable "app_port" {
  type    = number
  default = 8080
}

variable "keycloak_url" {
  type    = string
  default = "http://local-keycloak:8080"
}

variable "keycloak_public_url" {
  type    = string
  default = "http://localhost:11141"
}

variable "keycloak_realm" {
  type    = string
  default = "local-realm"
}

variable "keycloak_client_id" {
  type    = string
  default = "local-client"
}

variable "otlp_host" {
  description = "OTEL collector host. Java and Python use gRPC (otlp_grpc_port); DotNet uses OTLP/HTTP (otlp_http_port)."
  type        = string
  default     = "otel-collector"
}

variable "otlp_grpc_port" {
  type    = number
  default = 4317
}

variable "otlp_http_port" {
  type    = number
  default = 4318
}

locals {
  is_mssql     = var.db == "mssql"
  service_name = "${var.cloud}-${var.api_name}"

  otel_common = {
    OTEL_SERVICE_NAME        = local.service_name
    OTEL_RESOURCE_ATTRIBUTES = "service.instance.id=${local.service_name},db.variant=${var.db},cloud.provider=${var.cloud}"
  }

  dotnet = {
    ASPNETCORE_HTTP_PORTS                              = tostring(var.app_port)
    Application__DataConnections__0__Active            = "true"
    Application__DataConnections__0__DataSourceName    = local.is_mssql ? "NorthWind_SQL" : "NorthWind_Pgs"
    Application__DataConnections__0__Host              = var.host
    Application__DataConnections__0__Port              = tostring(var.port)
    Application__DataConnections__0__UserName          = var.user
    Application__DataConnections__0__Password          = var.password
    Application__DataConnections__0__ConnectTimeout    = "30"
    Application__Security__Active                      = "true"
    Application__Security__BaseUrl                     = var.keycloak_url
    Application__Security__PublicBaseUrl               = var.keycloak_public_url
    Application__Security__Realm                       = var.keycloak_realm
    Application__Security__ClientId                    = var.keycloak_client_id
    # PilotApiDotNet sets the OTLP endpoint in code from these two values (OTLP/HTTP),
    # and takes service.name from OpenApi:Title, so OTEL_SERVICE_NAME alone is not enough.
    Application__OpenTelemetry__Server                 = var.otlp_host
    Application__OpenTelemetry__Port                   = tostring(var.otlp_http_port)
    Application__OpenApi__Title                        = local.service_name
    OTEL_EXPORTER_OTLP_ENDPOINT                        = "http://${var.otlp_host}:${var.otlp_http_port}"
  }

  java_url = local.is_mssql ? "jdbc:sqlserver://${var.host}:${var.port};databaseName=NorthWind;encrypt=true;trustServerCertificate=true;connectTimeout=30" : "jdbc:postgresql://${var.host}:${var.port}/northwind"

  java = {
    SPRING_PROFILES_ACTIVE = local.is_mssql ? "prod-sqlserver" : "prod-postgres"
    SERVER_PORT            = tostring(var.app_port)
    DB_URL                 = local.java_url
    # application-prod-sqlserver.yml hard-codes the datasource URL, so the Spring
    # property is also set directly (OS env beats profile YAML).
    SPRING_DATASOURCE_URL            = local.java_url
    DB_USERNAME                      = var.user
    DB_PASSWORD                      = var.password
    APP_SECURITY_ACTIVE              = "true"
    APP_SECURITY_PROVIDER_URL        = var.keycloak_url
    APP_SECURITY_PUBLIC_PROVIDER_URL = var.keycloak_public_url
    APP_SECURITY_REALM               = var.keycloak_realm
    APP_SECURITY_CLIENT_ID           = var.keycloak_client_id
    OTEL_EXPORTER_OTLP_ENDPOINT      = "http://${var.otlp_host}:${var.otlp_grpc_port}"
  }

  python = merge(
    {
      APP_PORT                          = tostring(var.app_port)
      DB_BACKEND                        = local.is_mssql ? "sqlserver" : "postgresql"
      DB_HOST                           = var.host
      DB_PORT                           = tostring(var.port)
      DB_NAME                           = local.is_mssql ? "NorthWind" : "northwind"
      DB_SCHEMA                         = local.is_mssql ? "dbo" : "pilot"
      DB_USER                           = var.user
      DB_PASSWORD                       = var.password
      DB_CONNECT_TIMEOUT                = "30"
      DB_TRUST_SERVER_CERTIFICATE       = "true"
      LOG_JSON                          = "true"
      SECURITY_ACTIVE                   = "true"
      IDENTITY_PROVIDER_BASE_URL        = var.keycloak_url
      IDENTITY_PROVIDER_PUBLIC_BASE_URL = var.keycloak_public_url
      IDENTITY_PROVIDER_REALM           = var.keycloak_realm
      IDENTITY_PROVIDER_CLIENT_ID       = var.keycloak_client_id
      OTEL_EXPORTER_OTLP_ENDPOINT       = "http://${var.otlp_host}:${var.otlp_grpc_port}"
    },
    local.is_mssql ? { DB_DRIVER = "ODBC Driver 18 for SQL Server" } : {}
  )

  by_lang = {
    dotnet = local.dotnet
    java   = local.java
    python = local.python
  }
}

output "env" {
  description = "Container env vars (name => value)."
  value       = merge(local.by_lang[var.lang], local.otel_common)
  sensitive   = true
}

output "secret_names" {
  description = "Names of the env vars that hold the DB password (for platforms that support secret refs)."
  value       = var.lang == "dotnet" ? ["Application__DataConnections__0__Password"] : ["DB_PASSWORD"]
}
