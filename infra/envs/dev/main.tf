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
module "workload" {
  source = "../../modules/workload"

  environment           = var.environment
  image_repository      = var.image_repository
  image_tag             = var.image_tag
  location_short        = var.location_short
  owner                 = var.owner
  project_app_service   = var.project_app_service
  registry_login_server = var.registry_login_server
  tags                  = merge(local.common_tags, { environment = var.environment })
}
