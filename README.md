# parcelquote-platform

A reference implementation of a secretless Azure delivery pipeline: a containerised
FastAPI service deployed to Azure Container Apps, provisioned entirely with Terraform
and released through Azure Pipelines with progressive traffic shifting.

The application itself is deliberately small — a shipping quote API. The delivery
platform around it is the point.

## Architecture

Azure Pipelines builds and scans the container, pushes it to Azure Container Registry,
applies Terraform to provision infrastructure, then deploys a new Container Apps
revision and shifts traffic to it incrementally. Authentication to Azure uses workload
identity federation (OIDC): no Azure credential is stored anywhere, so nothing in the
provisioning and deployment path can leak one. The third-party quality gates are the
exception — SonarQube Cloud and Snyk authenticate with expiring API tokens held in Azure
DevOps service connections, because neither offers federation.

Phases 0 to 5 are complete: that identity chain is live, Terraform state is remote and
isolated per environment, and every commit to main is linted, tested, published to the
registry as an image tagged with its commit SHA, then deployed to a dev environment on
Container Apps. A smoke test confirms the running revision reports the commit that built
it. Pull requests run the same checks with no access to Azure.

Every commit also passes through gates that can stop it. Test results and coverage are
published to the run summary, a SonarCloud quality gate blocks on its conditions, Checkov
checks the Terraform, and Snyk tests the dependency tree and the built image before either
can reach the registry. Each gate has been watched failing as well as passing: a pinned
vulnerable dependency and a removed policy suppression both stop the build, which is the
difference between a gate that is trusted and one that is known to work.

Phase 4 adds the application's own secret, and where it lives is the point. `POST /quote`
now requires an API key; before that the service was open to anyone who found its hostname.
The key is held in Key Vault and resolved into the container by its managed identity, so it
appears in neither the repository nor Terraform state — Terraform handles the secret's
identifier and never its value. The pipeline that deploys the application cannot read it,
because Contributor grants no data-plane access under RBAC authorization and cannot grant
itself any, and every deploy asserts that rather than assuming it.

Phase 5 makes the platform observable, and the interesting part is what the numbers forced.
Container Apps logs now reach the workspace through a diagnostic setting rather than with its
shared key, which removed the last credential this project stored in the clear and unlocked
per-request status and latency. The application reports traces to Application Insights
authenticating as its managed identity, with ingestion keyed to Entra rather than an
instrumentation key. Three alerts and an availability test notify an action group, and a
subscription budget watches the spend — filtered to this project's resource groups, because the
subscription is shared and an unfiltered one would measure somebody else.

The thresholds were set against measured data rather than chosen, and two of them are the only
values that work. At two to eighteen requests an hour a failure *rate* is meaningless, and a
fifteen-minute window holds a single availability sample, so any threshold needing two failures
could never fire during an outage. The latency alert reads the application's own view rather
than the ingress's, because a cold start here takes 48 seconds and that time belongs in an
availability measure, not a latency one — the same measurement is why the availability test runs
with a 120-second timeout instead of the 30-second default that would have failed every check.

Progressive traffic shifting and production arrive with the phases below.

See [infra/bootstrap](infra/bootstrap/README.md) for how the foundational resources
are provisioned and what permissions they require,
[infra/envs/dev](infra/envs/dev/README.md) for the dev environment, what it reads from
bootstrap rather than creating, and the constraints worth knowing before changing it, and
[.azuredevops](.azuredevops/README.md) for the pipeline and the configuration it depends
on that lives in Azure DevOps rather than here.

## Stack

| Layer          | Technology                                                            |
| -------------- | --------------------------------------------------------------------- |
| Application    | Python 3.12, FastAPI                                                  |
| Container      | Docker (multi-stage, non-root)                                        |
| Registry       | Azure Container Registry                                              |
| Runtime        | Azure Container Apps (consumption, multi-revision)                    |
| Infrastructure | Terraform, remote state in Azure Storage with Entra auth              |
| CI/CD          | Azure Pipelines                                                       |
| Identity       | Entra ID workload identity federation, user-assigned managed identity |
| Secrets        | Azure Key Vault                                                       |
| Observability  | Application Insights, Log Analytics, OpenTelemetry                    |
| Quality gates  | pytest, ruff, SonarCloud, Snyk, Checkov                               |

## Status

Work in progress. Built in phases, each independently functional.

- [x] **Phase 0** — Repository, Azure DevOps project, federated identity, Terraform remote state
- [x] **Phase 1** — Application, tests, Dockerfile, CI to Container Registry
- [x] **Phase 2** — Dev environment provisioned with Terraform, continuous deployment
- [x] **Phase 3** — Code quality and security gates
- [x] **Phase 4** — Key Vault, managed identity and API authentication
- [x] **Phase 5** — Monitoring, alerting, availability tests and a cost budget
- [ ] **Phase 6** — Production environment, shared Terraform module, blue/green and canary releases
- [ ] **Phase 7** — Architecture documentation and decision records

## Repository layout

    .azuredevops/  Azure Pipelines definitions
    infra/         Terraform — bootstrap, and one configuration per environment from phase 2
    app/           FastAPI service, tests and Dockerfile

## Licence

MIT
