locals {
  common_tags = {
    workload   = var.project_app_service
    owner      = var.owner
    managed-by = "terraform"
    source     = "infra/bootstrap"
  }
  # Only dev builds images. Prod promotes an existing tag, so it needs no
  # push grant at all until that changes.
  image_build_environment = "dev"
  # Environments that run the container and therefore need to pull it.
  # Prod joins this list when its environment is built.
  deployment_environments = ["dev"]
  environment_resource_groups = {
    dev  = azurerm_resource_group.rg_dev
    prod = azurerm_resource_group.rg_prod
  }
  # Environments whose secrets an operator sets by hand. Dev only — a standing
  # human write grant on production secrets is not something to leave lying
  # around, so prod's will arrive another way. Deliberately an allow-list, so
  # adding an environment elsewhere cannot quietly grant one here.
  manual_secret_environments = ["dev"]
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
  # Customer-managed keys: considered and declined. Platform-managed keys already
  # encrypt this at rest, so CMK would buy key custody and cryptographic
  # revocation — neither of which this project has a requirement for. Against
  # that, a key that becomes unavailable makes the account unreadable, and the
  # state describing how to fix it lives in the account. Not worth it here.
  #checkov:skip=CKV2_AZURE_1:declined, see the comment above — custody we do not need, against locking Terraform out of its own state
  #checkov:skip=CKV2_AZURE_33:a private endpoint needs a VNet; state must stay reachable from hosted agents and laptops
  #checkov:skip=CKV_AZURE_59:same reason — public network access is what keeps state reachable
  #checkov:skip=CKV_AZURE_206:LRS is a deliberate cost choice; blob versioning and 7-day retention cover recovery
  #checkov:skip=CKV_AZURE_33:no queues are used on this account
  name                            = "st${var.project_app_service}tfst${var.location_short}01"
  location                        = azurerm_resource_group.rg_tfstate.location
  resource_group_name             = azurerm_resource_group.rg_tfstate.name
  account_tier                    = "Standard"
  account_replication_type        = "LRS"
  min_tls_version                 = "TLS1_2"
  https_traffic_only_enabled      = true
  public_network_access_enabled   = true
  shared_access_key_enabled       = false
  allow_nested_items_to_be_public = false
  tags                            = merge(local.common_tags, { environment = "tfstate" })

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
  #checkov:skip=CKV2_AZURE_21:declined — the only shape this check accepts is azurerm_log_analytics_storage_insights, whose storage_account_key is required, and shared_access_key_enabled is false on this account; satisfying it would mean putting an account key back into state to prove the account is monitored
  name                  = "tfstate"
  storage_account_id    = azurerm_storage_account.st_tfstate.id
  container_access_type = "private"
  lifecycle {
    prevent_destroy = true
  }
}

resource "azurerm_storage_container" "environment_state" {
  #checkov:skip=CKV2_AZURE_21:declined — the only shape this check accepts is azurerm_log_analytics_storage_insights, whose storage_account_key is required, and shared_access_key_enabled is false on this account; satisfying it would mean putting an account key back into state to prove the account is monitored
  for_each = toset(var.environments)

  name                  = "tfstate-${each.key}"
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
  for_each = var.pipeline_principal_ids

  scope                = azurerm_storage_container.environment_state[each.key].id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = each.value
  principal_type       = "ServicePrincipal"
}

resource "azurerm_role_assignment" "pipeline_environment_contributor" {
  for_each = var.pipeline_principal_ids

  scope                = local.environment_resource_groups[each.key].id
  role_definition_name = "Contributor"
  principal_id         = each.value
  principal_type       = "ServicePrincipal"
}

# ----------------------
# ACR
# ----------------------

resource "azurerm_container_registry" "cr_shared" {
  # The registry is Basic. Geo-replication, zone redundancy, dedicated data
  # endpoints, private networking, quarantine, content trust and untagged-manifest
  # retention are all Premium features, so none of these can be satisfied here.
  #checkov:skip=CKV_AZURE_139:private networking requires Premium
  #checkov:skip=CKV_AZURE_163:image scanning happens in the pipeline, not the registry
  #checkov:skip=CKV_AZURE_164:content trust requires Premium, and is superseded by cosign/Notation
  #checkov:skip=CKV_AZURE_165:geo-replication requires Premium; this is a single-region project
  #checkov:skip=CKV_AZURE_166:quarantine requires Premium
  #checkov:skip=CKV_AZURE_167:untagged-manifest retention requires Premium; buildcache growth is tracked manually
  #checkov:skip=CKV_AZURE_233:zone redundancy requires Premium
  #checkov:skip=CKV_AZURE_237:dedicated data endpoints require Premium
  name                          = "cr${var.project_app_service}${var.location_short}01"
  resource_group_name           = azurerm_resource_group.rg_shared.name
  location                      = azurerm_resource_group.rg_shared.location
  sku                           = "Basic"
  admin_enabled                 = false
  anonymous_pull_enabled        = false
  public_network_access_enabled = true
  role_assignment_mode          = "LegacyRegistryPermissions"
  tags                          = merge(local.common_tags, { environment = "shared" })

  lifecycle {
    prevent_destroy = true

    precondition {
      condition     = contains(var.environments, local.image_build_environment)
      error_message = "local.image_build_environment must name an entry in var.environments."
    }
    precondition {
      condition     = alltrue([for env in local.deployment_environments : contains(var.environments, env)])
      error_message = "Every entry in local.deployment_environments must name an entry in var.environments."
    }
  }
}

resource "azurerm_role_assignment" "acr_push" {
  for_each = { for env, id in var.pipeline_principal_ids : env => id if env == local.image_build_environment }

  scope                = azurerm_container_registry.cr_shared.id
  role_definition_name = "AcrPush"
  principal_id         = each.value
  principal_type       = "ServicePrincipal"
}

# ----------------------
# IDENTITY
# ----------------------

resource "azurerm_user_assigned_identity" "container_app" {
  for_each = toset(local.deployment_environments)

  name                = "id-${var.project_app_service}-${each.key}-${var.location_short}-01"
  resource_group_name = local.environment_resource_groups[each.key].name
  location            = local.environment_resource_groups[each.key].location
  tags                = merge(local.common_tags, { environment = each.key })
}

resource "azurerm_role_assignment" "acr_pull" {
  for_each = azurerm_user_assigned_identity.container_app

  scope                = azurerm_container_registry.cr_shared.id
  role_definition_name = "AcrPull"
  principal_id         = each.value.principal_id
  principal_type       = "ServicePrincipal"
}

# ----------------------
# KEY VAULT
# ----------------------

resource "azurerm_key_vault" "environment_key_vault" {
  # Five findings, three decisions. The two purge-protection checks are the same
  # test under different names, and the three networking ones each need either a
  # VNet or a stable source address. This vault has neither.
  #checkov:skip=CKV_AZURE_110:purge protection is off deliberately — see the comment on the attribute
  #checkov:skip=CKV_AZURE_42:the same test as CKV_AZURE_110 despite the name; it reads purge_protection_enabled, and the soft_delete_enabled it also names no longer exists in azurerm 5.x
  #checkov:skip=CKV_AZURE_189:passing this needs ip_rules or a subnet id, not necessarily closed access; hosted agents have no stable IP and consumption Container Apps no stable egress
  #checkov:skip=CKV_AZURE_109:network_acls default_action Deny needs the same stable source addresses CKV_AZURE_189 does
  #checkov:skip=CKV2_AZURE_32:a private endpoint needs a VNet, as with CKV2_AZURE_33 on the state account, and bills hourly at roughly £5 a month — more than every other resource in this project combined, to protect a vault holding one regenerable string
  for_each = toset(local.deployment_environments)

  # No '01' suffix, unlike every other resource here: with one this name is 25
  # characters and Key Vault caps at 24. Not an oversight — putting it back
  # produces a name Azure rejects.
  name                = "kv-${var.project_app_service}-${each.key}-${var.location_short}"
  resource_group_name = local.environment_resource_groups[each.key].name
  location            = local.environment_resource_groups[each.key].location
  sku_name            = "standard"
  tenant_id           = data.azurerm_client_config.current.tenant_id
  tags                = merge(local.common_tags, { environment = each.key })

  # Access policies would let anyone with Contributor on the resource group grant
  # itself secret read by adding a policy. RBAC keeps the data plane out of reach
  # of control-plane roles, which is what makes the pipeline identity unable to
  # read these secrets. Required in azurerm 5.x regardless — it has no default.
  rbac_authorization_enabled = true
  # Off deliberately: this vault holds regenerable application secrets, nothing
  # whose loss is unrecoverable, and it has to stay destroyable while the
  # environment is still being built.
  purge_protection_enabled = false
  # The minimum. Soft delete cannot be switched off, so a destroyed vault keeps
  # its globally-unique name reserved for this long — three months at the
  # default, which is a long time to wait to recreate one.
  soft_delete_retention_days = 7
  # Open question: whether Container Apps resolves a Key Vault reference from the
  # environment's outbound IP or from the Azure control plane. Until that is
  # established, network_acls with bypass = "AzureServices" could silently break
  # every new revision, so the firewall stays open.
  public_network_access_enabled = true

  lifecycle {
    # Guards local.manual_secret_environments, which governs kv_operator rather
    # than this resource. It cannot live there: when the filter matches nothing
    # that resource has no instances, so its preconditions never run — precisely
    # the case this is meant to catch. The vault always has one.
    precondition {
      condition = alltrue([
        for env in local.manual_secret_environments :
        contains(local.deployment_environments, env)
      ])
      error_message = "Every entry in local.manual_secret_environments must name an environment that has a vault, which means an entry in local.deployment_environments."
    }
  }
}

resource "azurerm_role_assignment" "kv_container_app" {
  for_each = azurerm_key_vault.environment_key_vault

  scope                = each.value.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_user_assigned_identity.container_app[each.key].principal_id
  principal_type       = "ServicePrincipal"
}

resource "azurerm_role_assignment" "kv_operator" {
  for_each = {
    for env, vault in azurerm_key_vault.environment_key_vault : env => vault
    if contains(local.manual_secret_environments, env)
  }

  scope                = each.value.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = data.azurerm_client_config.current.object_id
}
