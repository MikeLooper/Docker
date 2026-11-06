# Host form of the invoke URL (*.localhost.floci.io resolves to 127.0.0.1), $default stage.
output "api_base_urls" {
  value = { for k, a in aws_apigatewayv2_api.api : k => format(local.invoke_base, a.id) }
}

output "healthcheck_urls" {
  value = { for k, a in aws_apigatewayv2_api.api : k => "${format(local.invoke_base, a.id)}/healthcheck" }
}
