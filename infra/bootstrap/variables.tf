variable "environments" {
  type        = list(string)
  description = "Environment names that get their own resource group and state container."
  default     = ["dev", "prod"]
}

variable "location_long" {
  type        = string
  description = "The long-format Azure Region in which all resources will be created."
}

variable "location_short" {
  type        = string
  description = "The short-format Azure Region in which all resources will be created."
}

variable "project_app_service" {
  type        = string
  description = "The project app or service that the resource will be part of."
}

variable "az_subscription_id" {
  type        = string
  description = "Azure Subscription ID"
}

variable "owner" {
  type        = string
  description = "Email address of the person accountable for these resources."
}

variable "pipeline_principal_ids" {
  type        = map(string)
  description = "Service principal object IDs for each environment (keyed by environment)."
  default     = {}

  validation {
    condition = alltrue([
      for env in keys(var.pipeline_principal_ids) : contains(var.environments, env)
    ])
    error_message = "Keys must match an entry in var.environments."
  }
}
