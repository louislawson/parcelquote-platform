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

variable "devops_project_object_id" {
  type        = string
  description = "Object ID (principal_id) for the Devops Project linked to the Azure Subscription in the Entra ID."
  default     = ""
}

variable "az_subscription_id" {
  type        = string
  description = "Azure Subscription ID"
}

variable "owner" {
  type        = string
  description = "Email address of the person accountable for these resources."
}
