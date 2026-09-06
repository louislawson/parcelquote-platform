variable "environments" {
  type        = list(string)
  description = "Environments that receive a dedicated state container. Each entry also needs a matching resource group, which is declared explicitly rather than generated."
  default     = ["dev", "prod"]
}

variable "location_long" {
  type        = string
  description = "Azure region in long form, such as uksouth. All resources in this module are created here."
}

variable "location_short" {
  type        = string
  description = "Azure region abbreviation used in resource names, such as uks. Kept short because storage account names are limited to 24 characters."
}

variable "project_app_service" {
  type        = string
  description = "Workload name used in every resource name and the workload tag. Must be lowercase alphanumeric, as it forms part of the storage account name."
}

variable "az_subscription_id" {
  type        = string
  description = "Subscription all resources are created in. Supplied as a variable rather than hardcoded so the identifier stays out of the repository."
}

variable "owner" {
  type        = string
  description = "Email address of the person accountable for these resources, applied as the owner tag. This is who to contact before deleting anything."
}

variable "pipeline_principal_ids" {
  type        = map(string)
  description = "Service principal object IDs for each environment's Azure Pipelines identity, keyed by environment. Use the object ID of the Enterprise Application, not the app registration's object ID or its client ID. An empty map creates no role assignments."
  default     = {}

  validation {
    condition = alltrue([
      for env in keys(var.pipeline_principal_ids) : contains(var.environments, env)
    ])
    error_message = "Keys must match an entry in var.environments."
  }
}
