# 0001 — Azure Container Apps as the runtime

**Status:** Accepted

**Decided:** 2026-08-30

**Evidence:** PR #9, the first environment to run the container

## Context

The workload is a small containerised Python service, and the platform around it is the point of
the project. Three constraints applied from the start. The running cost had to be near zero,
because this is a reference implementation on a subscription shared with unrelated work. The
platform had to make blue/green and weighted traffic *first-class*, since demonstrating
progressive delivery honestly was one of the reasons for building it at all. And it had to be
something a single person could operate without a standing maintenance burden.

## Options considered

**Azure Kubernetes Service.** Rejected on standing cost and on scope. A control plane and at least
one node pool bill whether or not anything is being served, which breaks the first constraint
outright, and nothing about the work being demonstrated requires Kubernetes. It would also have
added an operational surface — upgrades, node images, cluster-scoped RBAC — with no reader for it.

**Azure App Service.** The closest alternative, and it fails on the combination rather than on any
single point. Deployment slots do support percentage traffic routing, so a canary is expressible,
but slots require Standard or higher, which bills continuously and therefore cannot scale to
zero. Slots are also a fixed set of named environments rather than one per deployment, so "the
previous revision" is a slot someone has to manage rather than a thing the platform keeps.

**Azure Container Instances.** No ingress model, no revisions, no traffic weights. It runs a
container; it is not a delivery platform.

## Decision

Azure Container Apps on the Consumption workload profile, scaled to zero when idle, with
production in multi-revision mode so that traffic weights are the deployment mechanism.

## Consequences

Rollback becomes a traffic shift rather than a redeployment: seconds, no rebuild, and the
outgoing revision is still running because nothing deactivated it. That single property is what
made phase 6 possible.

Scale to zero costs a cold start of about 48 seconds, measured in phase 5. That number then shaped
things that look unrelated to it: the availability test runs with a 120-second timeout so that
monitoring does not report an outage it caused itself, and the latency alert reads the
application's view rather than the ingress's, because a cold start belongs in an availability
measure and not a latency one.

**A revision suffix cannot be reused**, which is a platform property with consequences that
depend on what the suffix is made of. [0014](0014-multi-revision-mode-and-traffic-weights.md)
takes that decision and carries what it costs;
[docs/runbook.md](../runbook.md) states the measured rule and the recovery procedure.

Revisions accumulate in production, one per release, against a documented ceiling of 100 with
nothing counting them. They cost nothing, because billing follows replicas and an idle revision
has none.

And the Terraform provider reads three of this resource's attributes back wrongly, which is a
cost of the runtime choice as surely as the cold start is.
[infra/envs/prod/README.md](../../infra/envs/prod/README.md) records all three, and the one that
only bites in multi-revision mode belongs to
[0014](0014-multi-revision-mode-and-traffic-weights.md).
