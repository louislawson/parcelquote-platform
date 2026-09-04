output "tfstate_resource_group" {
  value = azurerm_resource_group.rg_tfstate.name
}

output "shared_resource_group" {
  value = azurerm_resource_group.rg_shared.name
}

output "dev_resource_group" {
  value = azurerm_resource_group.rg_dev.name
}

output "prod_resource_group" {
  value = azurerm_resource_group.rg_prod.name
}

output "tfstate_storage_account" {
  value = azurerm_storage_account.st_tfstate.name
}

output "tfstate_container" {
  value = azurerm_storage_container.tfstate.name
}

output "environment_state_containers" {
  value = { for env, container in azurerm_storage_container.environment_state : env => container.name }
}
