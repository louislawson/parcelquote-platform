output "app_fqdn" {
  description = "Stable hostname, serving whichever revisions the traffic weights point at."
  value       = one(azurerm_container_app.ca_dev.ingress).fqdn
}

output "latest_revision_fqdn" {
  description = "Hostname of the newest revision, reachable regardless of traffic weighting. The smoke test uses this so it asserts against the revision the run produced."
  value       = azurerm_container_app.ca_dev.latest_revision_fqdn
}

output "latest_revision_name" {
  description = "Name of the newest revision, for correlating container logs and shifting traffic."
  value       = azurerm_container_app.ca_dev.latest_revision_name
}
