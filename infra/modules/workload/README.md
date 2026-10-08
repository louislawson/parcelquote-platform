# Workload module

One environment's worth of the parcelquote service: the container app, the managed environment
it runs in, and everything that watches it. `infra/envs/dev` calls it today, and the production
environment will call it once that exists, differing only in the values it passes.

In Azure Verified Modules terms this is a **pattern module**, not a set of resource modules.
AVM's resource modules wrap a single primary resource and are forbidden from creating external
dependencies; its pattern modules compose several resources to serve a recognised architecture
and may be any size. The design spec called for five resource modules — naming, registry,
container_app, security and observability. Three of those are already elsewhere or not worth
having: the registry and the vault live in `infra/bootstrap`, and a naming module would add an
indirection that cannot validate anything the interpolated names do not already guarantee.
Splitting the remaining two would mean threading the workspace id, the app's FQDN and the
action group out of one module and into another, when nothing will ever instantiate one
without the other.

The narrower reason is that module boundaries buy flexibility for callers you do not control.
This module has two callers, both in this repository.

## What it creates

| Resource | Notes |
| -------- | ----- |
| Log Analytics workspace | Entra-only; local authentication is off |
| Container Apps managed environment | Consumption workload profile, `azure-monitor` log destination |
| Diagnostic setting | Console, system and HTTP logs to the workspace |
| Application Insights | Workspace-based, 1 GB/day cap, Entra-only ingestion |
| Container app | Scale-to-zero, managed-identity registry pull, Key Vault secret reference |
| Action group | One email receiver, the `owner` input |
| Scheduled query alerts | Server errors, and application-side p95 latency |
| Standard web test | `/healthz` from one location every fifteen minutes |
| Metric alert | Availability test failure |

## What it only reads

The resource group, the user-assigned identity and the key vault are created by
`infra/bootstrap` and looked up here by interpolated name. That is a deliberate departure from
HashiCorp's composition guidance, which would have the caller pass the ids in. A lookup built
from the naming convention cannot disagree with the convention, and the flexibility given up —
pointing a workload at resources that do not follow it — is not something this repository
will ever want. The cost lands on whoever adds an environment that breaks the pattern.

## Tags

`tags` arrives as a finished map and is applied verbatim; the caller merges the environment tag
in. The module does not build it, because the `source` tag records which configuration owns the
resource and that is the environment directory holding the state, not this directory. Asking
for the path as an input would leak the caller's layout into this interface.

`azurerm_monitor_diagnostic_setting` has no `tags` argument in the provider schema, so nine of
the ten resources here are tagged rather than all ten.

<!-- BEGIN_TF_DOCS -->
## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| candidate\_percentage | Share of production traffic sent to the revision this deployment creates. Ignored in Single mode, where the newest revision always takes everything. | `number` | `100` | no |
| environment | Environment name, used in every resource name and looked up to find the resource group, identity and vault bootstrap created for it. No validation here deliberately: the guard belongs in the calling configuration, which is the thing tied to one state container. | `string` | n/a | yes |
| image\_repository | Repository holding the image, without the registry host or a tag. | `string` | n/a | yes |
| image\_tag | Tag to run, normally the short commit SHA the pipeline built. The only input that changes between deployments, and changing it creates a new revision. | `string` | n/a | yes |
| location\_short | Azure region abbreviation used in resource names, such as uks. Must match the value bootstrap was applied with, since those names are used to look its resources up. | `string` | n/a | yes |
| owner | Email address of the person accountable for these resources. Also the action group's alert destination, which is why this is a separate input rather than something read out of tags. | `string` | n/a | yes |
| project\_app\_service | Workload name used in every resource name. Must match the value bootstrap was applied with. | `string` | n/a | yes |
| registry\_login\_server | Fully qualified registry host, such as crparcelquoteuks01.azurecr.io. Prefixes the image reference; the app authenticates to it with its managed identity. | `string` | n/a | yes |
| revision\_mode | Single or Multiple. Multiple is what makes the traffic weights meaningful, and it also stops Azure deactivating the outgoing revision — which is what a rollback shifts traffic back to. | `string` | n/a | yes |
| stable\_revision\_suffix | Suffix of the revision already serving production, which holds the remaining traffic while the new one is verified. Discovered from the live app by the caller rather than derived from git history, since the previous commit is not the previous deployment if a run was ever skipped. Naming one is what turns a deployment into a blue/green deployment: left empty, the newest revision takes everything as soon as Azure reports it ready. | `string` | `""` | no |
| tags | Tags applied to every taggable resource. The caller is expected to have merged the environment tag in already. | `map(string)` | n/a | yes |

## Outputs

| Name | Description |
|------|-------------|
| app\_fqdn | Stable hostname, serving whichever revisions the traffic weights point at. |
| candidate\_fqdn | Hostname of the green-labelled revision, reachable whatever share of traffic that revision carries, which is what allows a new revision to be verified before any traffic reaches it. Null in Single mode, where there is no label. |
| latest\_revision\_fqdn | Hostname of the newest revision as the provider last read it, for reading by hand. Stale by one revision immediately after an apply, so nothing automated should assert against it. |
| latest\_revision\_name | Name of the newest revision as the provider last read it, for correlating container logs by hand. Stale by one revision immediately after an apply, for the same reason as above. |
<!-- END_TF_DOCS -->

## Gotchas

**No provider block, deliberately.** A module cannot have its provider configuration overridden
by its caller, and one that carries its own breaks destroy ordering later. `terraform.tf` holds
the constraints and nothing else, which is the filename both HashiCorp's style guide and the
Azure Verified Modules spec give it — the root configurations call theirs `providers.tf`
because they have a provider to configure.

**`environment` carries no validation here.** The root configurations pin theirs to a single
value because each one's backend names a state container literally. That guard belongs with the
state, not with the resources.
