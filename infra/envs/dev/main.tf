locals {
  common_tags = {
    workload   = var.project_app_service
    owner      = var.owner
    managed-by = "terraform"
    source     = "infra/envs/dev"
  }
}

data "azurerm_resource_group" "rg_dev" {
  name = "rg-${var.project_app_service}-${var.environment}-${var.location_short}-01"
}

data "azurerm_user_assigned_identity" "container_app" {
  resource_group_name = data.azurerm_resource_group.rg_dev.name
  name                = "id-${var.project_app_service}-${var.environment}-${var.location_short}-01"
}

data "azurerm_key_vault" "kv_dev" {
  name                = "kv-${var.project_app_service}-${var.environment}-${var.location_short}"
  resource_group_name = data.azurerm_resource_group.rg_dev.name
}

resource "azurerm_log_analytics_workspace" "log_dev" {
  name                = "log-${var.project_app_service}-${var.environment}-${var.location_short}-01"
  location            = data.azurerm_resource_group.rg_dev.location
  resource_group_name = data.azurerm_resource_group.rg_dev.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
  tags                = merge(local.common_tags, { environment = var.environment })

  # Container Apps ships logs with the workspace's shared key, so this must stay
  # enabled while logs_destination is "log-analytics". See Gotchas in README.md.
  local_authentication_enabled = true
}

resource "azurerm_container_app_environment" "cae_env" {
  name                       = "cae-${var.project_app_service}-${var.environment}-${var.location_short}-01"
  location                   = data.azurerm_resource_group.rg_dev.location
  resource_group_name        = data.azurerm_resource_group.rg_dev.name
  logs_destination           = "log-analytics"
  log_analytics_workspace_id = azurerm_log_analytics_workspace.log_dev.id
  tags                       = merge(local.common_tags, { environment = var.environment })

  workload_profile {
    name                  = "Consumption"
    workload_profile_type = "Consumption"
  }
}

resource "azurerm_container_app" "ca_dev" {
  name                         = "ca-${var.project_app_service}-${var.environment}-${var.location_short}-01"
  container_app_environment_id = azurerm_container_app_environment.cae_env.id
  resource_group_name          = data.azurerm_resource_group.rg_dev.name
  revision_mode                = "Single"
  max_inactive_revisions       = 3
  workload_profile_name        = "Consumption"
  tags                         = merge(local.common_tags, { environment = var.environment })

  identity {
    type         = "UserAssigned"
    identity_ids = [data.azurerm_user_assigned_identity.container_app.id]
  }

  registry {
    server   = var.registry_login_server
    identity = data.azurerm_user_assigned_identity.container_app.id
  }

  # A Key Vault reference, not a value. Container Apps resolves it with the managed
  # identity, so the secret never passes through Terraform and lands in neither state
  # nor a plan file; replacing this with `value = ...` would put it in both. The id is
  # versionless and vault_uri already ends in a slash, so rotation needs no change
  # here — but it only takes effect on the next revision.
  secret {
    name                = "quote-api-key"
    identity            = data.azurerm_user_assigned_identity.container_app.id
    key_vault_secret_id = "${data.azurerm_key_vault.kv_dev.vault_uri}secrets/quote-api-key"
  }

  ingress {
    external_enabled           = true
    target_port                = 8000
    allow_insecure_connections = false
    traffic_weight {
      latest_revision = true
      percentage      = 100
    }
  }

  template {
    min_replicas = 0

    container {
      name   = "api"
      image  = "${var.registry_login_server}/${var.image_repository}:${var.image_tag}"
      cpu    = 0.25
      memory = "0.5Gi"

      env {
        name        = "QUOTE_API_KEY"
        secret_name = "quote-api-key"
      }

      liveness_probe {
        transport               = "HTTP"
        path                    = "/healthz"
        port                    = 8000
        initial_delay           = 5
        interval_seconds        = 10
        failure_count_threshold = 3
        timeout                 = 2
      }

      readiness_probe {
        transport               = "HTTP"
        path                    = "/readyz"
        port                    = 8000
        initial_delay           = 10
        interval_seconds        = 10
        failure_count_threshold = 3
        timeout                 = 2
      }
    }
  }
}
