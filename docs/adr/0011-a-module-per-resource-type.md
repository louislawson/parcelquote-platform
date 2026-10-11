# 0011 — A module per resource type

**Status:** Superseded by [0012](0012-one-workload-module.md)

**Decided:** 2026-08-30

**Evidence:** the layout the design called for, recorded in
[infra/modules/workload/README.md](../../infra/modules/workload/README.md)

## Context

The infrastructure needed a shape before any of it existed. The guidance everyone repeats is
that modules should be small and single-purpose, composed upwards into environments, so the
design named five: naming, registry, container_app, security and observability.

## Options considered

**Five resource modules.** Each wrapping one logical group, composed by each environment. The
conventional answer, and the one every published module registry demonstrates.

**One module per environment.** Rejected without much thought as the thing that produces two
environments which drift.

**No module at all.** Correct for exactly one environment, and phase 2 took it on that basis,
with the module deferred to whichever phase added a second.

## Decision

Five resource modules, as the target layout, to be built when a second environment makes them
necessary. Two decisions are bundled here and it is worth separating them, because only one is
superseded: the **target** is five resource modules, and the **interim** is no module at all
while there is one environment. [0012](0012-one-workload-module.md) replaces the target. The
interim was correct and ended when it was meant to.

## Consequences

Phase 2 ships `infra/envs/dev` with its resources inline, which is cheap and right for one
caller, and defers the work.

The deferral has a shape worth noting: whichever layout is eventually chosen, dev will already
exist and will have to be refactored into it, with state moves against live resources. The
longer the deferral runs, the more there is to move.
