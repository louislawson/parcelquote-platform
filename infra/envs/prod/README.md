# Production environment

The production environment for the parcelquote platform. It calls the shared
[workload module](../../modules/workload/README.md), which `infra/envs/dev` also calls, so the
two environments differ only in the values they pass and the state they own.

The pipeline applies this on every commit to main, **after dev has deployed and its smoke test
has passed, and after a manual approval**. Running it locally is for reading plans; applying by
hand bypasses the approval that is the point of this directory.

## What it creates

Nothing of its own. Everything below is created by the module and listed here because this is
where someone looks for it:

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

Four things belong to the bootstrap module and are looked up by interpolated name:
`rg-parcelquote-prod-uks-01`, `id-parcelquote-prod-uks-01`, `kv-parcelquote-prod-uks` and the
registry. Bootstrap creates them, grants the identity `AcrPull`, `Monitoring Metrics Publisher`
and `Key Vault Secrets User`, and is applied by hand — see
[infra/bootstrap/README.md](../bootstrap/README.md).

## How this differs from dev

Less than you would expect, and the differences are worth knowing precisely.

| | dev | prod |
| --- | --- | --- |
| Backend container and key | `tfstate-dev`, `dev.tfstate` | `tfstate-prod`, `prod.tfstate` |
| Deploy trigger | every commit to main | after dev succeeds, **and after approval** |
| Service connection | `azure-parcelquote-dev` | `azure-parcelquote-prod` |
| Registry access | `AcrPull` and `AcrPush` | **`AcrPull` only** |
| Operator access to the vault's secrets | `Key Vault Secrets Officer` | **none** |
| Revision mode | `Single` | **`Multiple`** |

The registry and vault rows are the two that matter for access. Prod's pipeline identity cannot
push an image, because prod promotes a tag dev already built rather than building its own. And no
human holds data-plane access to prod's vault: the key was written through a grant that was added
and removed in the same session, so the only thing that can read it is the container app's managed
identity. Both are enforced by allow-lists in bootstrap, not by convention here.

The revision mode row is the one that changes behaviour rather than access, and it is the only
input that makes this environment do something dev does not. Dev lets Azure deactivate the
previous revision as soon as the new one is ready. Prod keeps it running, which is what allows a
bad deployment to be undone by moving traffic instead of deploying again — and what makes
revisions accumulate. Its revision also carries a `green` label, giving it a second hostname that
reaches that revision whatever share of traffic it holds; `terraform output candidate_fqdn`
prints it.

Everything else — alert thresholds, the availability test's location and timeout, scale to zero,
probe configuration — is identical, because it comes from the module.

## This environment scales to zero

`min_replicas` is 0, so an idle production app cold-starts in about 48 seconds. That is a
deliberate cost choice for a reference implementation and it would be the wrong one for a
service with users. It shapes two things worth remembering: a caller that abandons a cold
start logs `StatusCode = 0` rather than a 5xx, and the availability test runs with a
120-second timeout against a 30-second default so that monitoring does not report an outage it
caused itself.

## Prerequisites

1. `infra/bootstrap` applied with `"prod"` in `local.deployment_environments` and a `prod`
   entry in `pipeline_principal_ids`
2. `quote-api-key` present in `kv-parcelquote-prod-uks`. The container app resolves the secret
   reference when it creates a revision, so without the value the first apply has nothing to
   resolve
3. An `azure-parcelquote-prod` service connection, and a `prod` environment in Azure DevOps
   carrying an **Approval** check and an **Exclusive Lock** check — see
   [.azuredevops/README.md](../../../.azuredevops/README.md)

## Running it

For reading a plan, not for applying. `owner` has no default, so supply it through
`terraform.tfvars` — copy `terraform.tfvars.example` — or `TF_VAR_owner`:

```bash
terraform -chdir=infra/envs/prod init
```

```bash
terraform -chdir=infra/envs/prod plan -var-file=prod.tfvars -var "image_tag=<short sha>"
```

The tag must name an image that exists in the registry. Prod never builds one, so a tag the
pipeline has not published will plan cleanly and then fail to start a revision.

<!-- BEGIN_TF_DOCS -->
## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| candidate\_percentage | Share of production traffic sent to the revision this deployment creates. The pipeline passes 0, verifies the revision on its own hostname, then passes 100. | `number` | `100` | no |
| environment | Environment name, used in every resource name and the environment tag. The backend block names its state container separately, so changing this alone does not repoint state. | `string` | `"prod"` | no |
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

**Applying this by hand defeats the approval.** The gate lives on the Azure DevOps `prod`
environment, which means it cannot be removed by editing the pipeline — but it also means it
does nothing at all when Terraform runs from a laptop. Local use is for plans.

**Prod's pipeline identity cannot read the vault, and the deploy asserts it.** The same
assertion that runs for dev runs here against prod's names, so the day someone grants this
identity `Key Vault Secrets User` to fix something unrelated, the build says so.

**Nobody can read prod's `quote-api-key`.** Exercising `POST /quote` against prod means either
holding the value from when it was set, or re-adding `prod` to
`local.manual_secret_environments` in bootstrap and applying twice. The smoke test does not
need it: `/healthz` and `/version` are unauthenticated.

**`prod.tfvars` is byte-identical to `dev.tfvars`.** None of those four values differ between
environments. That is duplication on purpose, so each configuration can be applied without
reading a file outside its own directory.

**`environment` and the backend are independent.** The backend block names `tfstate-prod`
literally, so changing `var.environment` renames resources without repointing state. The
variable is pinned by a `validation` block for exactly that reason.

**The approval timing out is a silent pass.** Azure DevOps marks a timed-out approval as
*skipped*, not failed, so the build goes green with prod never deployed. The timeout is left at
the 30-day default to make that effectively impossible rather than merely unlikely.

**Revisions accumulate here and nothing prunes them.** In `Multiple` mode no revision is
deactivated unless something deactivates it, and nothing does — so prod gains one active
revision per merge. They cost nothing, because billing follows replicas and an idle revision has
none, and `max_inactive_revisions` never applies to a revision that does not go inactive. The
real limit is Azure's own ceiling of 100 revisions with the oldest purged, and nothing reports
the count, so it is worth a look rather than a trust.

**A revision suffix is spent for the life of the app.** It is the short commit SHA, which makes
rolling back a traffic shift rather than a redeployment of the old tag — that suffix cannot be
used twice. The less obvious consequence: a change to the container template that arrives without
a new commit cannot be applied at all. Recreating Application Insights is the realistic way to
meet this, and the error will name a duplicate suffix rather than the cause.
