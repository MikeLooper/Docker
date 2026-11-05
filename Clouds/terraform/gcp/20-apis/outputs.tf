output "api_base_urls" {
  value = { for k, s in google_cloud_run_v2_service.api : k => s.uri }
}

output "healthcheck_urls" {
  value = { for k, s in google_cloud_run_v2_service.api : k => "${s.uri}/healthcheck" }
}
