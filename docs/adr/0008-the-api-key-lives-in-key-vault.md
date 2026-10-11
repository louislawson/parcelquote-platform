# 0008 — The API key lives in Key Vault, resolved by the app's own identity

**Status:** Accepted

**Decided:** 2026-09-28

**Evidence:** PR #19 and PR #20, and the standing assertion in
[templates/deploy-assertions.yml](../../.azuredevops/templates/deploy-assertions.yml)

## Context

`POST /quote` needed an API key; before phase 4 the service was open to anyone who found its
hostname. Key Vault was never in question. What had to be decided was who resolves the
reference and at what moment, because that determines which principals ever hold the value.

## Options considered

**A pipeline variable injected at deploy.** The value then lives in a variable group or a
service connection, every build has it, and it appears in the deployment path of a public
repository. It also makes the pipeline identity a secret holder, which is the opposite of what
the rest of the design is for.

**A secret value passed to Terraform.** It lands in state and in any plan file. State holds
resolved values and is the one artefact this repository most wants free of them.

**A versioned Key Vault reference resolved by the app's managed identity.** Keeps the value out
of everything, and pins the version — so every rotation becomes a configuration change and a
deployment.

**A versionless reference resolved by the app's managed identity.**

## Decision

A versionless Key Vault reference, resolved by the container app as itself at the moment it
creates a revision. Terraform handles the identifier and never the value.

## Consequences

The value appears in neither the repository, nor state, nor a plan, nor a build log. The
pipeline that deploys the application cannot read it, because Contributor grants no data-plane
access under RBAC authorization and cannot grant itself any — and **every deploy asserts that
rather than assuming it**, so the day someone adds `Key Vault Secrets User` to fix something
unrelated, the build says so.

Nobody holds production's key. It was written through a grant added and removed in the same
session, so exercising `POST /quote` against production means holding the value from then, or
re-adding the environment to the manual allow-list in bootstrap and applying twice. The smoke
test does not need it, because `/healthz` and `/version` are unauthenticated.

The cost lands in recovery: a lost production vault is a new key and every client updated, with
no copy anywhere to restore from. That is the intended trade and it is the right one here only
because the client is a smoke test.

And the versionless half of this decision had a consequence nobody understood for two phases.
See [0009](0009-rotation-requires-a-deployment.md).
