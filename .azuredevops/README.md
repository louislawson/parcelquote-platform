# Azure Pipelines

The pipeline definition, and the configuration it depends on that lives in Azure DevOps
rather than in this repository.

## Files

- `azure-pipelines.yml` — the pipeline: validate, publish, deploy to dev, deploy to prod
- `templates/install-terraform-tools.yml` — version-pinned installs of Terraform and
  tflint, each checksummed, with Terraform's checksums verified against a pinned
  HashiCorp signing key
- `templates/terraform-apply.yml` — one plan and apply of one environment at one traffic
  split. Dev calls it once and prod five times — the candidate created at 0%, three shifts and
  the rollback — which is why it is a template
- `templates/verify-traffic-split.yml` — measures how traffic is actually divided between two
  revisions, by asking which one answered
- `templates/deploy-assertions.yml` — the three checks that follow every apply: the smoke
  test, and the two standing assertions about the Key Vault grant and the alert receiver

## What the pipeline does

**Validate** runs on every pull request and every commit to main. It builds the
Dockerfile's test target, which runs ruff and pytest, builds the runtime target, and
checks formatting, validates and lints every Terraform configuration. It also checks the
documentation: that every generated Inputs and Outputs table matches the configuration it
describes, and that every relative link in the Markdown resolves. Nothing in this stage touches
Azure, so it runs with no credentials.

**Publish**, **Deploy to dev** and **Deploy to prod** run only on main. Publish builds the
runtime image with the short commit SHA as both its tag and its `GIT_SHA` build argument,
and pushes it to the container registry. Deploy to dev applies `infra/envs/dev`, then smoke
tests the result by polling `GET /version` until it reports the commit that built it.

**Deploy to prod** depends on dev rather than on Publish, so dev is prod's canary: the same
commit and image have already applied and passed a smoke test before anyone is asked to
approve. Prod promotes that tag rather than building its own, and its identity holds no
`AcrPush`, so a tag this run did not publish cannot be made to exist from there.

Prod deploys one revision at a time but keeps the previous one running, which is what lets a
bad release be undone by moving traffic instead of deploying again. The stage therefore
applies four times, each time asking Terraform for a different split, and checks between
every one.

It first reads the live app to find which revision is serving. Then it applies with the new
revision at **0%** — created, running, and reachable only on its own `---green` hostname. It
verifies there that the new revision answers with this commit *and* that the production
hostname is still answering with the previous one, which is what makes the first assertion
mean anything. Traffic then moves to **10%**, **50%** and **100%**, and after each shift the
split is *measured* rather than read back: a hundred or fifty requests to the production
hostname, counted by which commit answered. Session affinity is off, so the division is
decided per request, and `/version` names the revision that served it.

Neither intermediate weight buys a soak. This service sees a couple of requests an hour, so
there is no organic traffic to watch, and the alerts that might gate one run on fifteen-minute
windows. What they buy is proof that weighting works at all, and two earlier points at which a
revision that is broken under real traffic is caught.

Five plans are published under `terraform-plan-prod` — `plan-staged.txt`,
`plan-canary-10.txt`, `plan-canary-50.txt`, `plan-flip.txt` and, if it runs,
`plan-rollback.txt`. A re-run of a build that already deployed is a no-op: the discovery step
recognises that this commit is already serving, skips the staged applies, and leaves the
previous revision where a rollback would need it.

### If something fails

Any of those checks failing triggers a rollback: one more apply returning all traffic to the
previous revision, which is still running and still labelled `blue`. The build stays red —
the rollback restores service, it does not make the deployment a success.

There is one exception, and it is the case where rolling back would be the wrong thing to do.
Each measurement warms both revisions before sampling, so it is the only step that knows
*which* of the two will not answer. If the failure is the previous revision, the rollback
stands down rather than routing all of production at something already broken, and says so.
A failed deployment with production still on the new revision is a bad outcome; it is not the
worst one available.

A measurement tolerates up to two unanswered requests before failing. A revision that is
genuinely broken fails one request per request routed to it — about ten of a hundred at the
first canary step — while a single reset connection is one. Two separates those without
tolerating anything real, and the counts are printed either way.

Where the failure lands decides what was exposed. A revision that fails verification at 0%
never reaches production at all. One that fails at 10% or 50% served that share of requests
for the length of one apply, about thirty seconds, before being taken out of service. Neither
case needs anyone to be awake.

The rollback deliberately sits *before* the two standing assertions about the Key Vault grant
and the alert receiver, which say nothing about this revision. A vault grant that has drifted
is not fixed by moving traffic, and a rollback triggered by one would be a false remedy
dressed up as a safe one.

[docs/runbook.md](../docs/runbook.md) turns all of this into a procedure: what production is
serving at each failure point, how to roll back by hand when the rollback stood down, and what
not to reach for — the obvious recovery, re-queueing the previous good build, cannot work.

### Exercising the rollback

A rollback path nobody has watched work is a paragraph, so the pipeline has a runtime
parameter, **Deliberately fail prod's verification at this weight**, which can be set to `0`,
`10`, `50` or `100` when queueing a run by hand. The chosen measurement reports its real
result and then fails anyway, the rollback runs, and the run stays in the history as the
record.

It exists because a genuinely broken commit cannot be used instead: dev deploys first and its
smoke test fails, so prod never runs and the rollback never fires.

What makes it acceptable where a *skip* variable would not be is that it can only ever make
the pipeline stricter. Setting it causes a failure; there is no value that suppresses one, and
the parameter accepts nothing but those five words. Left alone it is `none`, and automatic
runs never set it.

Authentication to Azure is workload identity federation throughout. There is no stored
Azure credential in this repository or in the pipeline.

## Configuration that is not in this repository

Eight things the pipeline depends on that no file here declares. Recreating this pipeline
in a fresh Azure DevOps project means recreating them by hand.

### The Azure service connections

Two of them, one per environment, each referenced by name from the `AzureCLI@2` tasks in its
own stage: `azure-parcelquote-dev` and `azure-parcelquote-prod`. Both are Azure Resource
Manager connections using workload identity federation — no secret, no expiry to manage. Every
privilege either principal holds comes from the bootstrap module and nowhere else: dev has
Contributor on the dev resource group and `AcrPush` on the registry, prod has Contributor on
the prod resource group and **no** push grant at all, because production promotes a tag dev
already built.

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

### Two GitHub Apps, reporting from outside Azure DevOps

Both quality-gate vendors also have a GitHub App installed on the repository, and neither is
visible from the pipeline that way.

SonarQube Cloud's posts the **SonarCloud Code Analysis** check, carrying the quality gate from
the analysis the pipeline just performed. That is what puts the result on a pull request at
all, so it is a prerequisite for the gate rather than a second opinion.

Snyk's posts the `security/snyk` commit status and scans on its own account: it reported a pass
on a pull request that fired **no build whatsoever**, because the path filters excluded it. So
it is an integration holding repository access and publishing its own verdict, which is exactly
what this list exists to record. It is managed from Snyk's integrations page and, on the GitHub
side, under the repository's installed apps — not from the `snyk-parcelquote` service
connection, which carries nothing but the pipeline's token.

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

Six versions are pinned, and nothing automatically updates any of them. Automated updates
were investigated and declined: Dependabot has no Azure Pipelines ecosystem and no generic
manager, so it cannot see five of the six, and on a `FROM` line carrying a digest without a
tag it resolves the digest of `latest` — which would propose a Python interpreter migration as
a security update. Renovate can reach all of them through custom regex managers, and was declined
on the maintenance cost of five hand-written regexes that fail silently when they stop
matching.

| Pinned | Version | Where | How to bump |
| --- | --- | --- | --- |
| Terraform | `1.16.2` | `templates/install-terraform-tools.yml` | Version and SHA256 together; the command is in a comment beside the parameter |
| tflint | `v0.64.0` | `templates/install-terraform-tools.yml` | Version and SHA256 together; the command is in a comment beside the parameter |
| Checkov | `3.3.19` | `azure-pipelines.yml`, the `pipx install` step | Bump both the pin and the step's `displayName`, and the local install, or local and CI disagree |
| Snyk CLI | `v1.1307.4` | `azure-pipelines.yml`, `distributionChannel` on both Snyk tasks | `curl -s https://downloads.snyk.io/cli/stable/version`, then prefix `v` — the unprefixed path 403s |
| terraform-docs | `v0.20.0` | `azure-pipelines.yml`, the install step in the Terraform job | Version and SHA256 together, from the release's `.sha256sum`. Keep it equal to the version used locally, or the two disagree about what an up-to-date table looks like |
| Base image | digest | `app/Dockerfile` | See the comment above the `FROM` line |

Only the base image has anything watching it: Snyk's container gate catches it when a pinned
digest goes stale, which is how the perl-base advisories surfaced within about 36 hours. The
other five fail quietly by under-checking rather than by failing, so they need a periodic look
rather than a gate.

### The `dev` environment

Referenced as `environment: dev` by the deployment job. Azure DevOps creates an
environment on first reference, but it creates it empty — the check below has to be added
deliberately.

### The `prod` environment and its approval

Referenced as `environment: prod` by the production deployment job, and carrying two checks
that have to be added deliberately: an **Approval**, which is the whole reason production is a
separate stage, and an **Exclusive Lock**.

The approval's timeout is left at the 30-day default on purpose. Azure DevOps records a timed
out approval as *skipped* rather than failed, so a short timeout turns an unattended weekend
into a green build that deployed nothing.

### The exclusive lock check

An **Exclusive Lock** check on the `dev` environment, paired with `lockBehavior: runLatest`
on the deploy stage. The two only work together: the YAML setting says what to do when
runs queue behind the lock, and does nothing at all unless the check exists to create a
lock in the first place.

The `prod` environment carries the same check, where it also keeps two production runs from
interleaving traffic weights — each one reads the live weights once, before its first apply, and
then applies four times against that reading, so a second run starting in between would
invalidate it and leave each measuring the other's shift.

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

## Creating an Azure service connection, and why it is done by hand

Both Azure connections were created with the **manual** workload identity option, not the
automatic one, and that is deliberate. Automatic setup has Azure DevOps create the app
registration *and* assign it a role in Azure; manual setup has it create nothing. Since every
privilege these identities hold comes from `infra/bootstrap`, manual keeps that true —
`az role assignment list` against either principal returns exactly the assignments Terraform
made and nothing else. Automatic would also require Owner on the subscription.

The order matters, because the connection cannot be finished until the credential exists:

1. **Azure portal → App registrations → New registration.** Name it `sp-parcelquote-<env>`.
   Single tenant — "Accounts in this organizational directory only". **No redirect URI**: that
   field is for interactive sign-in, and this is the client credentials flow with a federated
   assertion. Copy the **Application (client) ID** and **Directory (tenant) ID**.
2. **Project settings → Service connections → New → Azure Resource Manager**, then "App
   registration or Managed identity (manual)" with the Workload identity federation
   credential. Name it `azure-parcelquote-<env>`, environment Azure Cloud, paste the tenant id.
3. Azure DevOps **generates** the **Issuer** and **Subject identifier** — copy both. Set scope
   level Subscription with the subscription id and name, paste the client id, and leave
   **Grant access permission to all pipelines** unticked. Choose **Keep as draft**.
4. **Back in the portal → the app registration → Certificates & secrets → Federated
   credentials → Add credentials → "Other issuer".** Paste the issuer and subject, set type to
   **Explicit subject identifier**, and save.
5. **Skip Microsoft's next step.** Their procedure ends by granting the app registration a role
   such as Contributor. Do not: `infra/bootstrap` grants it, and a second grant made here is a
   privilege Terraform does not know about. This is the one step in the vendor's instructions
   that must not be followed.
6. Back in Azure DevOps, **Finish setup** and save — see the next section about verification.
7. `az ad sp show --id <client-id> --query id -o tsv` gives the **Enterprise Application**
   object id for `pipeline_principal_ids`. Three GUIDs exist for one identity and only this one
   works; `infra/bootstrap/README.md` says the same thing where the variable is documented.

**Never add a client secret or a certificate.** Both connections have zero of each, and that is
what makes the claim of no stored Azure credential true rather than approximate.

New connections use the Microsoft Entra issuer, `https://login.microsoftonline.com/<tenant>/v2.0`.
The older Azure DevOps issuer, `https://vstoken.dev.azure.com`, **retires on 1 July 2027** —
Azure DevOps flags affected connections in the list with an **Update** button, and the guidance
is to convert the existing connection rather than replace it. `azure-parcelquote-prod` was
created on the Entra issuer and needs nothing; `azure-parcelquote-dev` predates that default
and should be checked.

## "Verify and save" fails, and should

Verifying a connection calls `Microsoft.Resources/subscriptions/read` at **subscription** scope:

    The client '...' with object id '...' does not have authorization to perform action
    'Microsoft.Resources/subscriptions/read' over scope '/subscriptions/...'

Neither pipeline identity holds a subscription-scoped role. Each has Contributor on one
resource group, Storage Blob Data Contributor on one state container, and — for dev only —
AcrPush on the registry. Contributor on a resource group does not confer subscription read, so
verification cannot pass, before or after `infra/bootstrap` runs. It is the scoping working.

Save without verifying. Do **not** grant Reader at subscription scope to make the check go
green: that is a standing privilege added to satisfy a validation step rather than a
requirement, and it would be invisible in Terraform.

Nothing in the pipeline needs subscription read. The deploy stage takes `ARM_SUBSCRIPTION_ID`
from `az account show`, which reads the login context rather than Azure Resource Manager.

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
2. Create the Azure Resource Manager service connection as `azure-parcelquote-dev` by the
   manual procedure in **Creating an Azure service connection** above, then apply
   `infra/bootstrap` so its principal holds the role assignments the pipeline needs. Expect
   verification to fail; that is covered above too
3. Create the pipeline from `azure-pipelines.yml`
4. Add the `OWNER` pipeline variable
5. Run it once; authorize the service connection at the prompt
6. Add the Exclusive Lock check to the `dev` environment that the first run created
7. Create `azure-parcelquote-prod` by the same manual procedure, then add its Enterprise
   Application object id to `pipeline_principal_ids` and `"prod"` to
   `local.deployment_environments` in `infra/bootstrap`, and apply it again
8. Write `quote-api-key` into the prod vault through the temporary grant described in
   bootstrap's README. The container app resolves the reference when it creates a revision, so
   without the value the first production apply has nothing to resolve
9. Create the `prod` environment with an **Approval** check and an **Exclusive Lock** check.
   Worth creating before the first production run rather than after, unlike dev's, since the
   approval is the point of the stage
10. Confirm fork builds are disabled in **Project settings → Pipelines → Settings**
11. Install the **SonarQube Cloud** and **Snyk Security Scan** extensions in the
    organization, then create the `sonarcloud-parcelquote` and `snyk-parcelquote` service
    connections and record their expiry dates above
12. In SonarQube Cloud, switch **Administration → Analysis Method → Automatic Analysis**
    off, or CI analysis is ignored and coverage never appears
13. Install the vendors' GitHub Apps. SonarQube Cloud's is required for the quality gate to
    appear on a pull request at all; Snyk's is optional and scans independently of this
    pipeline
