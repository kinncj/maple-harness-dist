output "fqdn" {
  description = "The app's name inside the environment's virtual network; add it to allowed_hosts."
  value       = azurerm_container_app.proxy.ingress[0].fqdn
}
