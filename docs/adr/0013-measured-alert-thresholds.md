# 0013 — Alert thresholds from measured data, and no failure-rate alert

**Status:** Accepted

**Decided:** 2026-10-04

**Evidence:** PR #28, and the thresholds and their reasoning in
[infra/modules/workload/main.tf](../../infra/modules/workload/main.tf)

## Context

Phase 5 added alerts and an availability test. This service receives something between two and
eighteen requests an hour, which is low enough that most standard alerting advice produces rules
that cannot fire, or fire constantly.

## Options considered

**A failure-rate alert**, which every reference architecture includes. At this volume a rate is
meaningless: one failed request in a two-request hour is fifty per cent, and a quiet hour has no
denominator at all.

**Thresholds copied from a reference architecture.** They encode an assumption about traffic
that is false here, and nobody would find out until an outage failed to page anyone.

**Thresholds derived from measured traffic**, accepting that they are specific to this workload.

## Decision

Measured. Server errors and application-side p95 latency as scheduled query rules, availability
as a metric alert on a web test, and no rate-based alert at all.

Two of the values are the only ones that work rather than the best of several. A fifteen-minute
window holds a single availability sample, so any threshold needing two failures could never
fire during an outage. And the latency alert reads the application's own view rather than the
ingress's, because a cold start of about 48 seconds belongs in an availability measure and not a
latency one.

## Consequences

The same measurement forced a value elsewhere that looks unrelated, and
[0016](0016-production-scales-to-zero.md) records it with the cold start that causes it.

The thresholds are not transferable. They are tuned to a traffic volume that will never change,
so copying them into a workload with users would be worse than copying the reference
architecture they replaced.

And the alerts reach an action group with one email receiver. Nothing escalates and nobody is
paged, so a correctly firing alert at 3am is an unread email — which makes this a monitoring
story rather than an incident-response one, and the architecture document says so.
