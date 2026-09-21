variable "environment" {
  type        = string
  description = "Environment name, used in every resource name and the environment tag. The backend block names its state container separately, so changing this alone does not repoint state."
  default     = "dev"

  validation {
    condition     = var.environment == "dev"
    error_message = "This directory is the dev environment and its backend names the tfstate-dev container literally. Another environment needs its own directory, not a different value here."
  }
}

variable "location_short" {
  type        = string
  description = "Azure region abbreviation used in resource names, such as uks. Must match the value bootstrap was applied with, since those names are used to look its resources up."
}

variable "project_app_service" {
  type        = string
  description = "Workload name used in every resource name and the workload tag. Must match the value bootstrap was applied with."
}

variable "az_subscription_id" {
  type        = string
  description = "Subscription all resources are created in. Supplied as a variable rather than hardcoded so the identifier stays out of the repository."
}

variable "owner" {
  type        = string
  description = "Email address of the person accountable for these resources, applied as the owner tag. This is who to contact before deleting anything."
}

variable "registry_login_server" {
  type        = string
  description = "Fully qualified registry host, such as crparcelquoteuks01.azurecr.io. Prefixes the image reference; the app authenticates to it with its managed identity."
}

variable "image_repository" {
  type        = string
  description = "Repository holding the image, without the registry host or a tag."
}

variable "image_tag" {
  type        = string
  description = "Tag to run, normally the short commit SHA the pipeline built. The only input that changes between deployments, and changing it creates a new revision."
}
