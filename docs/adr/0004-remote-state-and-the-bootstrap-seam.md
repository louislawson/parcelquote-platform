# 0004 — Remote state in Azure Storage, and a bootstrap applied by hand

**Status:** Accepted

**Decided:** 2026-09-03

**Evidence:** PR #2 and PR #3, and [infra/bootstrap/README.md](../../infra/bootstrap/README.md)

## Context

State has to be shared, locked and durable before a pipeline can apply anything. Two problems
arrive together: where state lives, and what creates the thing it lives in, given that Terraform
initialises its backend before it evaluates any configuration and so cannot create the account
the same run will use.

[0003](0003-federated-identity.md) had already settled that the pipeline identity would hold
Contributor and nothing more, which rules out that identity creating resource groups or writing
role assignments. Something else has to.

## Options considered

**Local state.** Not viable for anything a pipeline applies.

**Terraform Cloud or Enterprise.** A second identity system to federate, a third party holding
state that contains resolved values, and a dependency on somebody else's availability for every
apply. It solves locking well; it buys nothing else this project needs.

**One state for both environments.** Simpler to set up and the reason it is wrong is the whole
point of having two environments: a mistake in a dev apply would be a mistake in production's
state. It also makes per-environment data-plane isolation impossible.

**A storage account with one container per configuration**, created by a configuration applied
by hand.

## Decision

Azure Storage with Entra authentication and blob-lease locking, one container per configuration,
and `infra/bootstrap` applied by a human who holds the privileges a pipeline identity
deliberately lacks. Bootstrap was applied with local state and then migrated into the backend it
had just created.

## Consequences

Each pipeline identity has data access to its own container and no other. That is the isolation
worth having, and it forces a design choice downstream: the environment configurations find
bootstrap's resources with **data sources built from the naming convention**, not with
`terraform_remote_state`, because reading bootstrap's state from a pipeline run fails by design.
A lookup built from the convention cannot disagree with the convention, at the cost of being
unable to point an environment at resources that break it.

The operator who applies bootstrap holds `Storage Blob Data Contributor` at the account rather
than at a container, which makes that human the one principal able to read every environment's
state. State contains resolved values, so this is the sharpest asymmetry in the platform and it
is drawn in [docs/architecture.md](../architecture.md) rather than left implicit.

The account is locally redundant with blob versioning and a soft-delete window — a cost choice
recorded against the policy check it suppresses, and the wrong one for a service with users.

And the seam has a cost nobody paid until it was written down: a rebuild cannot run from code
alone. Bootstrap needs the object ids of service connections that must be created by hand first,
so it is applied twice around the pipeline's creation, and a from-scratch apply additionally
fails on the budget's `ForceNew` start date in any month after the committed one. Both are in
bootstrap's prerequisites; neither had ever been exercised.
