locals {
  common_tags = {
    workload   = var.project_app_service
    owner      = var.owner
    managed-by = "terraform"
    source     = "infra/envs/dev"
  }
}

# Everything this environment creates lives in the module; this file only says which
# environment it is. The source tag stays "infra/envs/dev" rather than naming the module,
# because it records which configuration owns the resource and that is still this directory —
# the module is shared, the state is not.
#
# Single revision mode, and not only because prod is the environment worth protecting. Dev's
# job is to fail fast and cost nothing, and multiple revisions would buy it an extra apply on
# every merge, revisions that are never deactivated, and a rollback path for a service nobody
# is depending on.
module "workload" {
  source = "../../modules/workload"

  environment           = var.environment
  image_repository      = var.image_repository
  image_tag             = var.image_tag
  location_short        = var.location_short
  owner                 = var.owner
  project_app_service   = var.project_app_service
  registry_login_server = var.registry_login_server
  revision_mode         = "Single"
  tags                  = merge(local.common_tags, { environment = var.environment })
}
