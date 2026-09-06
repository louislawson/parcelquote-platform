output "tfstate_resource_group" {
  description = "Resource group holding the Terraform state storage account. Used in the backend block of every module."
  value       = azurerm_resource_group.rg_tfstate.name
}

output "shared_resource_group" {
  description = "Resource group for resources shared across environments, such as the container registry."
  value       = azurerm_resource_group.rg_shared.name
}

output "dev_resource_group" {
  description = "Resource group the dev environment deploys into. The dev pipeline identity holds Contributor here and nowhere else."
  value       = azurerm_resource_group.rg_dev.name
}

output "prod_resource_group" {
  description = "Resource group the prod environment deploys into. The prod pipeline identity holds Contributor here and nowhere else."
  value       = azurerm_resource_group.rg_prod.name
}

output "tfstate_storage_account" {
  description = "Storage account holding Terraform state. Shared key access is disabled, so clients must authenticate with Entra ID."
  value       = azurerm_storage_account.st_tfstate.name
}

output "tfstate_container" {
  description = "Blob container holding this module's own state. Environment modules use their own containers instead."
  value       = azurerm_storage_container.tfstate.name
}

output "environment_state_containers" {
  description = "State container name for each environment, keyed by environment. Each pipeline identity can read and write only its own."
  value       = { for env, container in azurerm_storage_container.environment_state : env => container.name }
}
