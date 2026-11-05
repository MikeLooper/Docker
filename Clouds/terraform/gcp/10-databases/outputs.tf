output "mssql_host" {
  # The VM runs as a container on pilot-net; the SQL Server (_klt) container shares its
  # network namespace, so the VM container's name is the SQL Server host.
  value = "floci-gcp-${local.namespace}-compute-${local.project}-${local.zone}-${google_compute_instance.mssql.name}"
}

output "mssql_port" {
  value = 1433
}

output "postgres_host" {
  value = google_sql_database_instance.postgres.ip_address[0].ip_address
}

output "postgres_port" {
  value = 5432
}

output "postgres_admin_user" {
  # floci-gcp keeps the Cloud SQL admin login fixed (postgres/postgres).
  value = "postgres"
}
