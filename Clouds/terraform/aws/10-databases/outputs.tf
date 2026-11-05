output "mssql_host" {
  value = aws_db_instance.mssql.address
}

output "mssql_port" {
  value = aws_db_instance.mssql.port
}

output "postgres_host" {
  value = aws_db_instance.postgres.address
}

output "postgres_port" {
  value = aws_db_instance.postgres.port
}

output "vpc_id" {
  value = aws_vpc.cloud.id
}

output "subnet_ids" {
  value = [aws_subnet.a.id, aws_subnet.b.id]
}
