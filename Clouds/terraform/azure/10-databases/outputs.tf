output "mssql_host" {
  value = local.mssql_connect.host
}

output "mssql_port" {
  value = local.mssql_connect.port
}

output "postgres_host" {
  value = local.postgres_connect.host
}

output "postgres_port" {
  value = local.postgres_connect.port
}
