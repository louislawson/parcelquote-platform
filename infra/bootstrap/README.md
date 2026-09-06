# Bootstrap

Foundational Azure resources for the parcelquote platform. This is the only Terraform
in the repository intended to be run by hand — every other module runs in the pipeline.

## What it creates

- Resource groups: `tfstate`, `shared`, `dev`, `prod`
- Storage account and blob containers for Terraform remote state, one container per
  environment plus one for this module
- `Storage Blob Data Contributor` on the storage account for whoever runs the bootstrap
- Per-environment role assignments for the Azure Pipelines service principals:
  Contributor on the environment's resource group, and data-plane access to that
  environment's state container only

## Why it runs by hand

Two reasons.

Terraform initialises its backend before evaluating configuration, so the storage
account holding state cannot be created by the run that first uses it. This module was
applied with local state and then migrated.

More importantly, creating role assignments requires permission to write them. Keeping
that privilege in a module a human runs means the pipeline identities never need it —
they get Contributor on a single resource group and nothing else.

## Prerequisites

- Azure CLI, signed in (`az login`) to the correct subscription
- Owner or RBAC Administrator on the subscription — Contributor cannot create role
  assignments
- Terraform >= 1.16
- `terraform.tfvars`, copied from `terraform.tfvars.example` and filled in

## Running it

    terraform fmt
    terraform validate
    terraform plan "-out=bootstrap.tfplan"
    terraform apply bootstrap.tfplan

Quote `"-out=..."` in PowerShell. Unquoted, PowerShell splits the argument at the dot
and Terraform reports "Too many command line arguments", which does not obviously
describe the problem.

Read the plan before applying. There should never be a destroy — see the note on
`prevent_destroy` below.

<!-- BEGIN_TF_DOCS -->
## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| az\_subscription\_id | Subscription all resources are created in. Supplied as a variable rather than hardcoded so the identifier stays out of the repository. | `string` | n/a | yes |
| environments | Environments that receive a dedicated state container. Each entry also needs a matching resource group, which is declared explicitly rather than generated. | `list(string)` | ```[ "dev", "prod" ]``` | no |
| location\_long | Azure region in long form, such as uksouth. All resources in this module are created here. | `string` | n/a | yes |
| location\_short | Azure region abbreviation used in resource names, such as uks. Kept short because storage account names are limited to 24 characters. | `string` | n/a | yes |
| owner | Email address of the person accountable for these resources, applied as the owner tag. This is who to contact before deleting anything. | `string` | n/a | yes |
| pipeline\_principal\_ids | Service principal object IDs for each environment's Azure Pipelines identity, keyed by environment. Use the object ID of the Enterprise Application, not the app registration's object ID or its client ID. An empty map creates no role assignments. | `map(string)` | `{}` | no |
| project\_app\_service | Workload name used in every resource name and the workload tag. Must be lowercase alphanumeric, as it forms part of the storage account name. | `string` | n/a | yes |

## Outputs

| Name | Description |
|------|-------------|
| dev\_resource\_group | Resource group the dev environment deploys into. The dev pipeline identity holds Contributor here and nowhere else. |
| environment\_state\_containers | State container name for each environment, keyed by environment. Each pipeline identity can read and write only its own. |
| prod\_resource\_group | Resource group the prod environment deploys into. The prod pipeline identity holds Contributor here and nowhere else. |
| shared\_resource\_group | Resource group for resources shared across environments, such as the container registry. |
| tfstate\_container | Blob container holding this module's own state. Environment modules use their own containers instead. |
| tfstate\_resource\_group | Resource group holding the Terraform state storage account. Used in the backend block of every module. |
| tfstate\_storage\_account | Storage account holding Terraform state. Shared key access is disabled, so clients must authenticate with Entra ID. |
<!-- END_TF_DOCS -->

The container names feed the backend blocks of the per-environment modules.

## Adding a pipeline identity

`pipeline_principal_ids` takes the **service principal object ID** — the Enterprise
Application entry in Entra ID, not the app registration's own object ID and not its
Application (client) ID. All three are GUIDs and only one works.

    az ad sp show --id <application-client-id> --query id -o tsv

Add it under the environment's key and apply. An empty map creates no assignments, so
environments without a pipeline identity are simply skipped.

## Gotchas

**Role assignments take minutes to propagate.** An `AuthorizationPermissionMismatch`
immediately after a successful apply usually means waiting, not misconfiguration. That
error means authentication succeeded and authorisation failed — distinct from
`AuthenticationFailed`, which means the identity itself was not recognised.

**Control plane and data plane are separate.** Owner and Contributor govern the storage
account as a resource; neither grants access to the blobs inside it. That is why the
`Storage Blob Data Contributor` assignments exist and why `az storage` commands against
this account need `--auth-mode login` — shared key access is disabled.

**`prevent_destroy` blocks replacement, not just destruction.** It is set on the storage
account and every state container. A change that would force a new storage account —
renaming it, for instance — fails the plan rather than recreating it. Removing a
protected resource from configuration removes the protection along with it, so the
resource is then destroyed on the next apply.
