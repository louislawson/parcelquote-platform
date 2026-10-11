# 0015 — The canary measures the split and gates on nothing proportional

**Status:** Accepted

**Decided:** 2026-10-09

**Evidence:** PR #39, and builds 66 and 69

## Context

[0014](0014-multi-revision-mode-and-traffic-weights.md) moves traffic to the new revision in
steps. Each step needs a check, and the check has to mean something: a deployment that asserts
only what it just asked for proves nothing it did not already know.

## Options considered

**Read the weights back from the API.** Proves Azure recorded the number that was sent. It does
not prove that a single request reached the new revision, which is the thing actually in doubt.

**Gate on the observed proportion.** Tempting, and it would fail correct deployments. The
measured splits were 11 of 100 at the 10 per cent step and 31 of 50 at 50 per cent — ordinary
binomial spread at those sample sizes. A tolerance band wide enough never to fire falsely is
wide enough to be worthless.

**Sample the production hostname and count which commit answered**, failing only when the
candidate is absent where it should be present, or present where it should be absent.

## Decision

Measure by sampling — a hundred requests at 10 per cent, fifty at 50 and fifty at 100 — and gate
on presence rather than on proportion.

## Consequences

The evidence is real rather than reported back: session affinity is off, so the division is
decided per request, and `/version` names the revision that served it. The final check is the
strongest in the stage, because at 100 per cent *every* request must report the new commit — so
a residual weight left on the outgoing revision fails there and would pass the smoke test that
follows it.

It costs about two hundred extra requests per release against a service that otherwise sees a
couple an hour. That is free in money and does mean the canary is most of production's traffic
for the minute it runs.

**What it cannot do is prove a revision healthy.** There is no load for it to be healthy under,
so the observation is synthetic: it proves that weighting works, and gives two earlier points at
which a revision that is broken outright is caught. The README and the runbook both say so,
because this is the claim a reader is most likely to round up.
