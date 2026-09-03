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
identity federation (OIDC) — there are no stored credentials anywhere in the pipeline.

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

- [ ] **Phase 0** — Repository, Azure DevOps project, federated identity, Terraform remote state
- [ ] **Phase 1** — Application, tests, Dockerfile, CI to Container Registry
- [ ] **Phase 2** — Terraform modules, dev environment, continuous deployment
- [ ] **Phase 3** — Code quality and security gates
- [ ] **Phase 4** — Key Vault and managed identity
- [ ] **Phase 5** — Monitoring, alerting and availability tests
- [ ] **Phase 6** — Production environment, blue/green and canary releases
- [ ] **Phase 7** — Architecture documentation and decision records

## Repository layout

    app/      FastAPI service, tests and Dockerfile
    infra/    Terraform — bootstrap, reusable modules, per-environment roots
    docs/     Architecture documentation and decision records

## Licence

MIT
