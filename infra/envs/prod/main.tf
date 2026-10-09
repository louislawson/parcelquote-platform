locals {
  common_tags = {
    workload   = var.project_app_service
    owner      = var.owner
    managed-by = "terraform"
    source     = "infra/envs/prod"
  }
}

# Everything this environment creates lives in the module; this file only says which
# environment it is. The source tag stays "infra/envs/prod" rather than naming the module,
# because it records which configuration owns the resource and that is still this directory —
# the module is shared, the state is not.
#
# Multiple revision mode is the one input that makes this environment behave differently from
# dev rather than just carry different names. It keeps the outgoing revision running, which is
# what allows a bad deployment to be undone by moving traffic rather than by deploying again.
# The cost is that nothing deactivates those revisions, so they accumulate.
module "workload" {
  source = "../../modules/workload"

  candidate_percentage   = var.candidate_percentage
  environment            = var.environment
  image_repository       = var.image_repository
  image_tag              = var.image_tag
  location_short         = var.location_short
  owner                  = var.owner
  project_app_service    = var.project_app_service
  registry_login_server  = var.registry_login_server
  revision_mode          = "Multiple"
  stable_revision_suffix = var.stable_revision_suffix
  tags                   = merge(local.common_tags, { environment = var.environment })
}
