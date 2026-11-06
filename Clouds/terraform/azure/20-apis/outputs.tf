# Container Apps ingress is the Azure front door. floci-az routes requests on port 4577
# by Host header; with FLOCI_AZ_SERVICES_CONTAINER_APPS_DNS_SUFFIX=localhost the app
# FQDNs end in .localhost, which browsers and curl resolve to 127.0.0.1.
# (APIM is not used: floci-az's APIM gateway forwards no client headers, so the
# Authorization header never reaches the APIs.)
output "api_base_urls" {
  value = { for k, a in azurerm_container_app.api : k => "http://${a.ingress[0].fqdn}:4577" }
}

output "healthcheck_urls" {
  value = { for k, a in azurerm_container_app.api : k => "http://${a.ingress[0].fqdn}:4577/healthcheck" }
}
