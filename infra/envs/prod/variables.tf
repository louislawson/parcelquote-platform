variable "environment" {
  type        = string
  description = "Environment name, used in every resource name and the environment tag. The backend block names its state container separately, so changing this alone does not repoint state."
  default     = "prod"

  validation {
    condition     = var.environment == "prod"
    error_message = "This directory is the prod environment and its backend names the tfstate-prod container literally. Another environment needs its own directory, not a different value here."
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

# The two inputs below exist so that one pipeline template can apply either environment. They
# are passed to the module on every run and ignored by it in Single revision mode, where the
# newest revision always takes all the traffic. Declaring them in both environments keeps the
# two directories symmetric, which is the same reason their tfvars files are identical.
variable "stable_revision_suffix" {
  type        = string
  description = "Suffix of the revision already serving production, discovered from the live app by the pipeline rather than held in the repository. Naming one is what turns a deployment into a blue/green deployment; left empty, the newest revision takes everything once Azure reports it ready."
  default     = ""
}

variable "candidate_percentage" {
  type        = number
  description = "Share of production traffic sent to the revision this deployment creates. The pipeline passes 0, verifies the revision on its own hostname, then passes 100."
  default     = 100
}
