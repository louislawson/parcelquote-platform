# Development environment

The dev environment for the parcelquote platform: a Container Apps environment running
the image the pipeline built, and the Log Analytics workspace its logs land in.

The pipeline applies this on every commit to main. Running it locally is for iterating,
and uses your own identity rather than the pipeline's.

## What it creates

- Log Analytics workspace, 30-day retention
- Container Apps environment with a single Consumption workload profile
- Container app serving the quote API over HTTPS, scaled to zero when idle

## What it only reads

Three things belong to the bootstrap module and are looked up here rather than created:

- `rg-parcelquote-dev-uks-01`, the resource group everything lands in. The pipeline
  identity holds Contributor here and nowhere else, and could not create a resource
  group in any case, since that needs write at subscription scope.
- `id-parcelquote-dev-uks-01`, the managed identity the container app pulls with.
  Bootstrap also grants it `AcrPull` on the registry, because a pipeline identity cannot
  create role assignments.
- The container registry, addressed by login server rather than by resource. Nothing
  here needs its resource ID.

They are found with data sources rather than `terraform_remote_state`. A pipeline
identity has data access to the `tfstate-dev` container and no other, so bootstrap's own
state is unreadable from a pipeline run.

## Why the image tag is an input

`image_tag` is the only variable that changes between deployments, and changing it is
what produces a new revision. The pipeline passes the short commit SHA of the build that
produced the image, so a running revision is always traceable to a commit.

`GET /version` on that revision returns the same value. It is baked into the image at
build time rather than injected here, so the answer comes from the artefact rather than
from the platform that happens to be running it.

## Revisions

`revision_mode` is `Single`: one revision serves all traffic and the previous one is
deactivated on each apply. The `traffic_weight` block is required by the schema
regardless, and is ignored until the mode changes. Phase 6 switches to `Multiple` for
blue/green and canary, which is an in-place update rather than a replacement.

`revision_suffix` is deliberately unset. Deriving it from the image tag would read
better in the portal, but a suffix must be unique for the life of the app and a build
can be re-run against an unchanged commit.

## Workload profile

The environment declares one `Consumption` workload profile, and the app names it in
`workload_profile_name`. The platform creates new environments with that profile whether
or not it is declared, so leaving it out does not produce a different kind of
environment — it produces a plan that tries to remove the profile on every run.

The Consumption profile is still per-second billing with scale-to-zero. Dedicated
profiles can be added later without recreating the environment, but the last profile
can never be removed: an environment created with profiles must always have at least
one.

## Prerequisites

- Azure CLI, signed in to the correct subscription
- Contributor on the dev resource group and data access to the `tfstate-dev` container
- Bootstrap applied, so the resource group, identity and registry exist
- An image tag that exists in the registry
- `terraform.tfvars`, copied from `terraform.tfvars.example` and filled in

## Running it

    terraform init
    terraform fmt
    terraform validate
    terraform plan "-out=dev.tfplan"
    terraform apply dev.tfplan

Quote `"-out=..."` in PowerShell, for the same reason as the bootstrap module.

<!-- BEGIN_TF_DOCS -->
## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| az\_subscription\_id | Subscription all resources are created in. Supplied as a variable rather than hardcoded so the identifier stays out of the repository. | `string` | n/a | yes |
| environment | Environment name, used in every resource name and the environment tag. The backend block names its state container separately, so changing this alone does not repoint state. | `string` | `"dev"` | no |
| image\_repository | Repository holding the image, without the registry host or a tag. | `string` | n/a | yes |
| image\_tag | Tag to run, normally the short commit SHA the pipeline built. The only input that changes between deployments, and changing it creates a new revision. | `string` | n/a | yes |
| location\_short | Azure region abbreviation used in resource names, such as uks. Must match the value bootstrap was applied with, since those names are used to look its resources up. | `string` | n/a | yes |
| owner | Email address of the person accountable for these resources, applied as the owner tag. This is who to contact before deleting anything. | `string` | n/a | yes |
| project\_app\_service | Workload name used in every resource name and the workload tag. Must match the value bootstrap was applied with. | `string` | n/a | yes |
| registry\_login\_server | Fully qualified registry host, such as crparcelquoteuks01.azurecr.io. Prefixes the image reference; the app authenticates to it with its managed identity. | `string` | n/a | yes |

## Outputs

| Name | Description |
|------|-------------|
| app\_fqdn | Stable hostname, serving whichever revisions the traffic weights point at. |
| latest\_revision\_fqdn | Hostname of the newest revision, reachable regardless of traffic weighting. The smoke test uses this so it asserts against the revision the run produced. |
| latest\_revision\_name | Name of the newest revision, for correlating container logs and shifting traffic. |
<!-- END_TF_DOCS -->

## Gotchas

**Scale to zero means the first request is slow.** `min_replicas` is 0, so an idle app
cold-starts on the next request. A smoke test needs a retry rather than a single call —
one impatient `curl` looks exactly like a failed deployment.

**Registry authentication needs both blocks.** `identity` attaches the managed identity
to the app; `registry.identity` tells the app to authenticate with it. Supplying only
the second is accepted by Terraform and fails when the revision tries to pull.

**The workspace keeps local authentication enabled, and has to.** Container Apps sends
logs to Log Analytics with the workspace's shared key: the provider reads the primary
key and writes it into the environment's log configuration. Disabling local
authentication blocks key-based ingestion without anything reporting it — reading the
key is a control-plane call authorised by RBAC, so the apply still succeeds, and logs
simply stop arriving. The same mechanism is why the workspace keys appear in this
module's state. An Entra-only workspace means switching to
`logs_destination = "azure-monitor"` with a diagnostic setting that targets this
workspace, which authenticates through the Azure Monitor control plane instead of the
key.

**Probe ports are not checked against the container.** Liveness and readiness point at
the app's own `/healthz` and `/readyz` on port 8000. A probe aimed at the wrong port
passes both plan and apply, then restarts the container in a loop so the revision never
goes healthy — which reads like a broken image rather than a configuration error.

**`environment` and the backend are independent.** The backend block names `tfstate-dev`
literally, so changing `var.environment` repoints every resource name without repointing
state.
