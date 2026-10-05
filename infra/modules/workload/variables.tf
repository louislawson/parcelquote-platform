variable "environment" {
  type        = string
  description = "Environment name, used in every resource name and looked up to find the resource group, identity and vault bootstrap created for it. No validation here deliberately: the guard belongs in the calling configuration, which is the thing tied to one state container."
}

variable "location_short" {
  type        = string
  description = "Azure region abbreviation used in resource names, such as uks. Must match the value bootstrap was applied with, since those names are used to look its resources up."
}

variable "project_app_service" {
  type        = string
  description = "Workload name used in every resource name. Must match the value bootstrap was applied with."
}

variable "owner" {
  type        = string
  description = "Email address of the person accountable for these resources. Also the action group's alert destination, which is why this is a separate input rather than something read out of tags."
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

# Built by the caller rather than here, and not only as a style choice. The source tag records
# which configuration owns the resource, and after this module existed that answer is still the
# environment directory holding the state — a module cannot know it, and asking for the path as
# an input would leak the caller's layout into this interface. Taking the finished map also
# matches the tags interface Azure Verified Modules standardises on.
variable "tags" {
  type        = map(string)
  description = "Tags applied to every taggable resource. The caller is expected to have merged the environment tag in already."
}
