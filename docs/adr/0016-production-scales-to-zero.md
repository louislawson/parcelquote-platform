# 0016 — Production scales to zero

**Status:** Accepted

**Decided:** 2026-10-07

**Evidence:** PR #35, and the cold start measured in phase 5

## Context

Production and dev call the same module, and `min_replicas` is not one of its inputs: it is the
literal `0`, written once and applied to both. So production scaling to zero was decided by
*not* adding a per-environment input for it, which is a decision rather than an inheritance and
easy to mistake for one, since nothing in either environment's configuration mentions it.

## Options considered

**One warm replica in production only.** A production service with users would have this. It
costs twice over: roughly doubling the standing charge of the whole platform, since a
continuously running container is a larger bill than the registry, and widening the shared
module's interface for the benefit of one caller — the tension
[0012](0012-one-workload-module.md) records, where prod-only behaviour has nowhere to live
except an input both environments see.

**Scale to zero**, accepting a cold start on the first request after an idle period.

## Decision

Zero, as a property of the module rather than a value production passes.

## Consequences

An idle production app cold-starts in about 48 seconds, measured rather than estimated, and
nearly all of that is the platform pulling the image and starting the container rather than
anything the application does.

That number propagates into places that look unrelated to it. The availability test runs with a
120-second timeout against a 30-second default, so monitoring does not report an outage it
caused itself. The latency alert reads the application's own view, because a cold start belongs
in an availability measure. And a caller that gives up during one logs `StatusCode = 0` rather
than a 5xx, which looks like a client error and is not.

**The normal state of a healthy production service here is no running instance**, so "is
production up?" cannot be answered by looking for a replica. The runbook opens with the three
checks that do answer it.

This is the wrong choice for a service with users, and the production README says so outright
rather than leaving a reader to infer that a reference implementation is a template.
