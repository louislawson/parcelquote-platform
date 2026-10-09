# Development environment

The dev environment for the parcelquote platform: a Container Apps environment running
the image the pipeline built, and the Log Analytics workspace its logs land in.

The pipeline applies this on every commit to main. Running it locally is for iterating,
and uses your own identity rather than the pipeline's.

The resources themselves live in the shared
[workload module](../../modules/workload/README.md), which the production environment will
call too once it exists. This directory holds the state, the backend that names it, the tags,
and the values that make this environment dev. The list below is what the module creates on
its behalf.

## What it creates

- Log Analytics workspace, 30-day retention, Entra-only
- Container Apps environment with a single Consumption workload profile
- Diagnostic setting sending the environment's console, system and HTTP logs to that
  workspace
- Workspace-based Application Insights, Entra-only ingestion, 1 GB daily cap
- Container app serving the quote API over HTTPS, scaled to zero when idle
- Action group with one email receiver, taking the address from `var.owner`
- Three alerts: server errors and request latency as scheduled query rules, and availability
  as a metric alert on the web test below
- Standard availability test polling `/healthz` from one location every fifteen minutes

## What it only reads

Four things belong to the bootstrap module and are looked up here rather than created:

- `rg-parcelquote-dev-uks-01`, the resource group everything lands in. The pipeline
  identity holds Contributor here and nowhere else, and could not create a resource
  group in any case, since that needs write at subscription scope.
- `id-parcelquote-dev-uks-01`, the managed identity the container app pulls with.
  Bootstrap also grants it `AcrPull` on the registry, because a pipeline identity cannot
  create role assignments.
- The container registry, addressed by login server rather than by resource. Nothing
  here needs its resource ID.
- `kv-parcelquote-dev-uks`, the vault holding the application's secrets. Only its URI is
  read — the value is never fetched here, so nothing about the secret reaches state. The
  container app's identity holds `Key Vault Secrets User` on it, granted by bootstrap for
  the same reason as `AcrPull`.

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

- Azure CLI, signed in. The provider takes its subscription from `ARM_SUBSCRIPTION_ID` if
  set, otherwise from the CLI's default subscription, so check `az account show` first
- Contributor on the dev resource group and data access to the `tfstate-dev` container
- Bootstrap applied, so the resource group, identity, registry and vault exist
- The `quote-api-key` secret present in the vault. Bootstrap creates the vault and the
  grants but not the value, which is set by hand
- `terraform.tfvars`, copied from `terraform.tfvars.example` and filled in

## Running it

`image_tag` is an output of a build rather than a setting, so it is not kept in
`terraform.tfvars`. The pipeline passes the commit SHA it just published. A local run
should pass back whatever is already deployed, so the plan shows only the change being
made rather than an image rollback:

    TAG=$(az containerapp show -n ca-parcelquote-dev-uks-01 -g rg-parcelquote-dev-uks-01       --query "properties.template.containers[0].image" -o tsv | cut -d: -f2)

    terraform init
    terraform fmt
    terraform validate
    terraform plan -var-file=dev.tfvars -var "image_tag=$TAG" "-out=dev.tfplan"
    terraform apply dev.tfplan

Quote `"-out=..."` in PowerShell, for the same reason as the bootstrap module.

Applying from a laptop should be rare. The pipeline owns this environment; local runs are
for planning a change before pushing it, for state operations such as imports and moves,
and for recovering when a pipeline run has failed partway through an apply.

<!-- BEGIN_TF_DOCS -->
## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| candidate\_percentage | Share of production traffic sent to the revision this deployment creates. The pipeline passes 0, verifies the revision on its own hostname, then passes 100. | `number` | `100` | no |
| environment | Environment name, used in every resource name and the environment tag. The backend block names its state container separately, so changing this alone does not repoint state. | `string` | `"dev"` | no |
| image\_repository | Repository holding the image, without the registry host or a tag. | `string` | n/a | yes |
| image\_tag | Tag to run, normally the short commit SHA the pipeline built. The only input that changes between deployments, and changing it creates a new revision. | `string` | n/a | yes |
| location\_short | Azure region abbreviation used in resource names, such as uks. Must match the value bootstrap was applied with, since those names are used to look its resources up. | `string` | n/a | yes |
| owner | Email address of the person accountable for these resources, applied as the owner tag. This is who to contact before deleting anything. | `string` | n/a | yes |
| project\_app\_service | Workload name used in every resource name and the workload tag. Must match the value bootstrap was applied with. | `string` | n/a | yes |
| registry\_login\_server | Fully qualified registry host, such as crparcelquoteuks01.azurecr.io. Prefixes the image reference; the app authenticates to it with its managed identity. | `string` | n/a | yes |
| stable\_revision\_suffix | Suffix of the revision already serving production, discovered from the live app by the pipeline rather than held in the repository. Naming one is what turns a deployment into a blue/green deployment; left empty, the newest revision takes everything once Azure reports it ready. | `string` | `""` | no |

## Outputs

| Name | Description |
|------|-------------|
| app\_fqdn | Stable hostname, serving whichever revisions the traffic weights point at. |
| candidate\_fqdn | Hostname of the green-labelled revision, reachable whatever share of traffic that revision carries, which is what allows a new revision to be verified before any traffic reaches it. Null in Single mode, where there is no label. |
| latest\_revision\_fqdn | Hostname of the newest revision as the provider last read it, for reading by hand. Stale by one revision immediately after an apply, so nothing automated should assert against it. |
| latest\_revision\_name | Name of the newest revision as the provider last read it, for correlating container logs by hand. Stale by one revision immediately after an apply, for the same reason as above. |
<!-- END_TF_DOCS -->

## Gotchas

**Scale to zero means the first request is slow.** `min_replicas` is 0, so an idle app
cold-starts on the next request. A smoke test needs a retry rather than a single call —
one impatient `curl` looks exactly like a failed deployment.

**Registry authentication needs both blocks.** `identity` attaches the managed identity
to the app; `registry.identity` tells the app to authenticate with it. Supplying only
the second is accepted by Terraform and fails when the revision tries to pull.

**A secret reference is invisible in the plan.** Terraform marks the whole `secret` block
sensitive, because `value` is a sensitive attribute in the schema even when unused. So
`key_vault_secret_id` never appears in plan output, nor in the `plan.txt` the pipeline
publishes for review, and a wrong secret name looks exactly like a right one. It fails at
revision creation instead, with an error that reads like a permissions problem. Check the
revision after a deploy rather than trusting the plan.

**Local authentication and the log destination are coupled.** The workspace is
Entra-only, which is only possible because the environment ships logs through a
diagnostic setting — that route authenticates through the Azure Monitor control plane
rather than with the workspace's shared key. Reverting `logs_destination` to
`log-analytics` puts the key back in the path, and so back into this module's state.

The failure in that direction is silent. Under `log-analytics` the provider reads the
primary key and writes it into the environment's log configuration; reading it is a
control-plane call authorised by RBAC, so with local authentication off the apply still
succeeds and logs simply stop arriving, with nothing reporting it. Change the two
together or not at all.

**Log table names changed with the destination.** Each category lands in its own table:
`ContainerAppConsoleLogs`, `ContainerAppSystemLogs` and `ContainerAppHTTPLogs`. That is a
property of the resource type rather than something configured — a managed environment
supports only resource-specific tables, so `log_analytics_destination_type` is
unconfigurable here and setting it produced a change on every plan while altering nothing.

Anything written before the switch is still in the `ContainerAppConsoleLogs_CL` and
`ContainerAppSystemLogs_CL` custom tables, which keep their history and stop growing. A
query against a `_CL` table therefore does not fail — it returns old rows and looks
healthy, which is the trap.

**Probe ports are not checked against the container.** Liveness and readiness point at
the app's own `/healthz` and `/readyz` on port 8000. A probe aimed at the wrong port
passes both plan and apply, then restarts the container in a loop so the revision never
goes healthy — which reads like a broken image rather than a configuration error.

**`environment` and the backend are independent.** The backend block names `tfstate-dev`
literally, so changing `var.environment` repoints every resource name without repointing
state.

**An alert's scope decides its table names, and the two tables disagree.** Both scheduled
query rules are scoped to the workspace, where Application Insights data lives under
`AppRequests`, `AppTraces` and so on. Scope a rule to the Application Insights component
instead and the same data is queried as `requests` — so a query copied between the two
names a table that does not exist. That much is caught at apply, because
`skip_query_validation` is left at its default of `false`.

What is not caught is picking the wrong one deliberately. `ContainerAppHTTPLogs` is the
ingress's view and `AppRequests` is the application's, and over identical traffic they
reported a p95 of roughly 24 ms and 2 ms, with maxima of 48,224 ms and 2 ms. The difference
is the time a caller spends waiting for a cold container, which belongs in an availability
measure rather than a latency one. The latency alert reads `AppRequests` for that reason.

**The availability test's timeout has to clear the cold start.** It defaults to 30 seconds
and a measured cold start here is 48, so the default fails every test that finds the app
asleep — monitoring reporting an outage it caused itself. It is set to 120, with
`retry_enabled` as well, since the first attempt wakes the container and a retry lands warm.

**The availability test location tags do not match the regions they name.** UK South is
`emea-ru-msa-edge`; North Europe is `emea-gb-db3-azr`. They are historical and Microsoft's
own documentation has an open issue about them, so read them from the API rather than a list:

    GET <application insights id>/syntheticmonitorlocations?api-version=2015-05-01
