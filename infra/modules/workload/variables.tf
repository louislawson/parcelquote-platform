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

# No default, although Single would be a reasonable one. Which revision mode an environment runs
# in decides whether a bad deployment can be undone by shifting traffic or only by deploying
# again, so it belongs where someone reading that environment's configuration will see it rather
# than inherited silently from here.
variable "revision_mode" {
  type        = string
  description = "Single or Multiple. Multiple is what makes the traffic weights meaningful, and it also stops Azure deactivating the outgoing revision — which is what a rollback shifts traffic back to."

  validation {
    condition     = contains(["Single", "Multiple"], var.revision_mode)
    error_message = "revision_mode must be Single or Multiple. Deployment labels is a third mode in preview, but the provider does not offer it."
  }
}

variable "stable_revision_suffix" {
  type        = string
  description = "Suffix of the revision already serving production, which holds the remaining traffic while the new one is verified. Discovered from the live app by the caller rather than derived from git history, since the previous commit is not the previous deployment if a run was ever skipped. Naming one is what turns a deployment into a blue/green deployment: left empty, the newest revision takes everything as soon as Azure reports it ready."
  default     = ""
}

# One number, not two. The provider requires the weights to total exactly 100 with no defaults
# assumed, so the stable revision takes the remainder here instead of being passed its own
# percentage that could disagree. It also reduces the canary to a list of single values.
variable "candidate_percentage" {
  type        = number
  description = "Share of production traffic sent to the revision this deployment creates. Ignored in Single mode, where the newest revision always takes everything."
  default     = 100

  validation {
    condition     = var.candidate_percentage >= 0 && var.candidate_percentage <= 100
    error_message = "candidate_percentage must be between 0 and 100."
  }

  # Scoped to Multiple mode as well as to the empty suffix, because Single mode ignores this
  # value entirely and rejecting it there would fail with a complaint about weights that mode
  # never writes.
  validation {
    condition     = var.revision_mode == "Single" || var.stable_revision_suffix != "" || var.candidate_percentage == 100
    error_message = "With no stable revision to hold the remainder, candidate_percentage must be 100, or the weights cannot total 100."
  }
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
