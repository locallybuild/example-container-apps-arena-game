output "arena_url" {
  description = "Public HTTPS URL of the arena game (the container app's ingress FQDN)."
  value       = "https://${azurerm_container_app.arena.ingress[0].fqdn}"
}

output "resource_group" {
  value = azurerm_resource_group.arena.name
}

output "log_analytics_workspace_name" {
  description = "Log Analytics workspace paired with the Container App Environment (Dashboard -> Monitoring -> Workspaces)."
  value       = azurerm_log_analytics_workspace.arena.name
}
