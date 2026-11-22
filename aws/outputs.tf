output "rds_endpoint" {
  value       = aws_db_instance.pgdb.endpoint
  description = "PostgreSQL connection host:port"
}

output "rds_address" {
  value       = aws_db_instance.pgdb.address
  description = "PostgreSQL hostname"
}

output "ecs_cluster_name" {
  value       = aws_ecs_cluster.pax_cluster.name
  description = "Name of the deployed ECS cluster"
}

output "internal_service_dns" {
  value = {
    keycloak = "kc.pax.local:8080"
    pax_api  = "pax-api.pax.local:8080"
  }
  description = "Private Cloud Map DNS names accessible between ECS tasks"
}