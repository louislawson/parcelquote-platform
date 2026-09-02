locals {
  common_tags = {
    workload   = var.project_app_service
    owner      = var.owner
    managed-by = "terraform"
    source     = "infra/bootstrap"
  }
}

data "azurerm_client_config" "current" {}

# ----------------------
# RESOURCE GROUP
# ----------------------

resource "azurerm_resource_group" "rg_tfstate" {
  name     = "rg-${var.project_app_service}-tfstate-${var.location_short}-01"
  location = var.location_long
  tags     = merge(local.common_tags, { environment = "tfstate" })
}

resource "azurerm_resource_group" "rg_shared" {
  name     = "rg-${var.project_app_service}-shared-${var.location_short}-01"
  location = var.location_long
  tags     = merge(local.common_tags, { environment = "shared" })
}

resource "azurerm_resource_group" "rg_dev" {
  name     = "rg-${var.project_app_service}-dev-${var.location_short}-01"
  location = var.location_long
  tags     = merge(local.common_tags, { environment = "dev" })
}

resource "azurerm_resource_group" "rg_prod" {
  name     = "rg-${var.project_app_service}-prod-${var.location_short}-01"
  location = var.location_long
  tags     = merge(local.common_tags, { environment = "prod" })
}

# ----------------------
# STORAGE
# ----------------------

resource "azurerm_storage_account" "st_tfstate" {
  name                          = "st${var.project_app_service}tfst${var.location_short}01"
  location                      = azurerm_resource_group.rg_tfstate.location
  resource_group_name           = azurerm_resource_group.rg_tfstate.name
  account_tier                  = "Standard"
  account_replication_type      = "LRS"
  min_tls_version               = "TLS1_2"
  https_traffic_only_enabled    = true
  public_network_access_enabled = true
  shared_access_key_enabled     = false
  tags                          = merge(local.common_tags, { environment = "tfstate" })

  blob_properties {
    versioning_enabled = true
    delete_retention_policy {
      days = 7
    }
    container_delete_retention_policy {
      days = 7
    }
  }

  lifecycle {
    prevent_destroy = true
  }
}

resource "azurerm_storage_container" "tfstate" {
  name                  = "tfstate"
  storage_account_id    = azurerm_storage_account.st_tfstate.id
  container_access_type = "private"
  lifecycle {
    prevent_destroy = true
  }
}

resource "azurerm_role_assignment" "tfstate_operator" {
  scope                = azurerm_storage_account.st_tfstate.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = data.azurerm_client_config.current.object_id
}

resource "azurerm_role_assignment" "tfstate_pipeline" {
  count = var.devops_project_object_id == "" ? 0 : 1

  scope                = azurerm_storage_account.st_tfstate.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = var.devops_project_object_id
  principal_type       = "ServicePrincipal"
}
