# Azure Pipelines

The pipeline definition, and the configuration it depends on that lives in Azure DevOps
rather than in this repository.

## Files

- `azure-pipelines.yml` — the pipeline: validate, publish, deploy to dev
- `templates/install-terraform-tools.yml` — version-pinned installs of Terraform and
  tflint, each checksummed, with Terraform's checksums verified against a pinned
  HashiCorp signing key

## What the pipeline does

**Validate** runs on every pull request and every commit to main. It builds the
Dockerfile's test target, which runs ruff and pytest, builds the runtime target, and
checks formatting, validates and lints every Terraform configuration. Nothing in this
stage touches Azure, so it runs with no credentials.

**Publish** and **Deploy to dev** run only on main. Publish builds the runtime image with
the short commit SHA as both its tag and its `GIT_SHA` build argument, and pushes it to
the container registry. Deploy applies `infra/envs/dev`, then smoke tests the result by
polling `GET /version` until it reports the commit that built it.

Authentication to Azure is workload identity federation throughout. There is no stored
Azure credential in this repository or in the pipeline.

## Configuration that is not in this repository

Six things the pipeline depends on that no file here declares. Recreating this pipeline
in a fresh Azure DevOps project means recreating them by hand.

### The Azure service connection

Named `azure-parcelquote-dev`, referenced by name from every `AzureCLI@2` task. It is an
Azure Resource Manager connection using workload identity federation — no secret, no
expiry to manage. Its service principal holds Contributor on the dev resource group and
`AcrPush` on the registry, both granted by the bootstrap module.

The deploy step reads `AZURESUBSCRIPTION_CLIENT_ID`, `AZURESUBSCRIPTION_TENANT_ID` and
`AZURESUBSCRIPTION_SERVICE_CONNECTION_ID` from it and hands them to the azurerm provider
as `ARM_*` values, so Terraform mints its own tokens rather than riding the CLI session.
`ARM_USE_CLI=false` is the guard: without it, an incomplete OIDC configuration silently
falls back to the CLI login and the run passes while proving nothing.

### The quality gate service connections

Two connections carry the SaaS gates, and unlike the Azure one they hold real secrets.

| Connection | Gate | Credential | Expires |
| --- | --- | --- | --- |
| `sonarcloud-parcelquote` | SonarQube Cloud analysis and quality gate | Personal access token | **2026-12-25** |
| `snyk-parcelquote` | Snyk dependency and container scanning | Personal access token | **2026-12-26** |

Both are personal tokens belonging to an organisation owner, because project-scoped
alternatives are paid features on both platforms — SonarQube Cloud's Scoped Organization
Tokens need the Team plan, and Snyk's service accounts are likewise not on the free tier.
A leaked token would therefore grant whatever that account can do in its organisation.

What bounds that: the tokens live only in the service connections, never in the
repository; fork pull requests receive no secrets, and do not build at all; and either can
be revoked immediately, from **My account → Access tokens** in SonarQube Cloud or
**Account settings → Auth tokens** in Snyk.

**The expiry dates above are load-bearing.** Nothing warns the pipeline that a token is
about to lapse, and when one does the affected step fails with an authentication error
rather than anything that points here. Renew both and update this table.

### When a SaaS gate is down

Both Snyk tasks fail the build on tool errors as well as on findings, deliberately: a gate
that passes when it could not evaluate manufactures confidence. Two retries absorb a single
bad response, but not a sustained outage — on 6 October 2026 a Snyk incident failed two
consecutive builds roughly eight minutes apart, and the same commit passed unchanged the next
morning.

So the first move is to check whether the vendor is actually down rather than inferring it
from build history: <https://status.snyk.io> and <https://sonarcloud.statuspage.io>. Waiting is
usually correct, because nothing here has an SLA and the cost of not deploying for a few hours
is nil.

**If something genuinely must ship while a gate is unreachable**, edit the pipeline to remove
the failing task, ship, and revert — three commits, all in the history. There is deliberately
no skip variable: a variable is the same bypass with less of a trace, and the point of a
fail-closed gate is that going around it leaves a record. The one thing not to do is flip
`failOnIssues` to `false` and forget, because that is indistinguishable from a passing gate
forever afterwards.

### Pinned tool versions

Five versions are pinned, and nothing automatically updates any of them. Automated updates
were investigated and declined: Dependabot has no Azure Pipelines ecosystem and no generic
manager, so it cannot see four of the five, and on a `FROM` line carrying a digest without a
tag it resolves the digest of `latest` — which would propose a Python interpreter migration as
a security update. Renovate can reach all five through custom regex managers, and was declined
on the maintenance cost of five hand-written regexes that fail silently when they stop
matching.

| Pinned | Version | Where | How to bump |
| --- | --- | --- | --- |
| Terraform | `1.16.2` | `templates/install-terraform-tools.yml` | Version and SHA256 together; the command is in a comment beside the parameter |
| tflint | `v0.64.0` | `templates/install-terraform-tools.yml` | Version and SHA256 together; the command is in a comment beside the parameter |
| Checkov | `3.3.19` | `azure-pipelines.yml`, the `pipx install` step | Bump both the pin and the step's `displayName`, and the local install, or local and CI disagree |
| Snyk CLI | `v1.1307.4` | `azure-pipelines.yml`, `distributionChannel` on both Snyk tasks | `curl -s https://downloads.snyk.io/cli/stable/version`, then prefix `v` — the unprefixed path 403s |
| Base image | digest | `app/Dockerfile` | See the comment above the `FROM` line |

Only the base image has anything watching it: Snyk's container gate catches it when a pinned
digest goes stale, which is how the perl-base advisories surfaced within about 36 hours. The
other four fail quietly by under-checking rather than by failing, so they need a periodic look
rather than a gate.

### The `dev` environment

Referenced as `environment: dev` by the deployment job. Azure DevOps creates an
environment on first reference, but it creates it empty — the check below has to be added
deliberately.

### The exclusive lock check

An **Exclusive Lock** check on the `dev` environment, paired with `lockBehavior: runLatest`
on the deploy stage. The two only work together: the YAML setting says what to do when
runs queue behind the lock, and does nothing at all unless the check exists to create a
lock in the first place.

The effect is that concurrent deploys serialise, and when several runs queue only the
latest proceeds — the superseded ones are cancelled at the lock rather than skipped
earlier, so every commit still publishes an image tagged with its SHA even when its deploy
never happens.

**Rejected: `trigger: batch: true`.** It is one line in the YAML and needs no environment
configuration, but it batches at the *source* — several commits become one run, and the
commits in the middle never produce an image at all. Being able to point at any commit on
main and find its image is worth the extra piece of configuration.

### The `OWNER` pipeline variable

A plain, non-secret pipeline variable holding an email address. It reaches Terraform as
`TF_VAR_owner` and ends up as the `owner` tag on every resource the dev environment
creates.

It needs the explicit `env:` mapping in the YAML because Azure DevOps uppercases variable
names when it exports them, while Terraform matches `TF_VAR_` names case-sensitively. A
variable named `owner` in the library arrives as `OWNER` in the process environment, which
Terraform does not recognise.

## First-use authorization looks like a failure

The first pipeline run to reference a protected resource — a service connection, an
environment, a variable group — pauses and reports that it needs permission before it can
continue. This is not an error. Someone with access to the resource authorizes it once in
the run's own UI, and it never asks again for that pipeline.

Expect it once per new protected resource.

## Fork pull requests do not build

Fork protection is enabled at the project level with fork builds switched off, so a pull
request from a fork of this repository runs nothing. The pipeline's own trigger settings
also refuse secrets and full-access tokens to fork builds, so both layers agree.

The consequence worth knowing: an outside contributor's pull request gets no CI at all.
Validating one means fetching the branch into this repository and pushing it.

## The Triggers page holds a stale branch filter — leave it alone

The pipeline's pull request trigger stores `branchFilters: ["+feat/smoke-pipeline"]`, a
leftover from an early branch. It has no effect: the trigger's settings source is the YAML
file, so the `pr:` block in `azure-pipelines.yml` governs, and pull requests into main
validate normally.

It is invisible in the UI, sitting behind an unticked **Override the YAML pull request
trigger from here**. Clearing it means ticking that box — and leaving the box ticked would
move pull request triggering out of the committed file and into pipeline settings nobody
reviews. The untidiness is safer than the fix.

It can be seen through the REST API, on the build definition under `triggers`.

## Recreating this in a fresh project

1. Work through **Prerequisites** in [infra/bootstrap/README.md](../infra/bootstrap/README.md)
   first — it lists the subscription-scoped setup a pipeline identity cannot do for itself,
   including two resource provider registrations. They are not repeated here, because two
   copies of a checklist is how one of them goes stale
2. Create the Azure Resource Manager service connection as `azure-parcelquote-dev`, using
   workload identity federation, and apply `infra/bootstrap` so its principal holds the
   role assignments the pipeline needs
3. Create the pipeline from `azure-pipelines.yml`
4. Add the `OWNER` pipeline variable
5. Run it once; authorize the service connection at the prompt
6. Add the Exclusive Lock check to the `dev` environment that the first run created
7. Confirm fork builds are disabled in **Project settings → Pipelines → Settings**
8. Install the **SonarQube Cloud** and **Snyk Security Scan** extensions in the
   organization, then create the `sonarcloud-parcelquote` and `snyk-parcelquote` service
   connections and record their expiry dates above
9. In SonarQube Cloud, switch **Administration → Analysis Method → Automatic Analysis**
   off, or CI analysis is ignored and coverage never appears
