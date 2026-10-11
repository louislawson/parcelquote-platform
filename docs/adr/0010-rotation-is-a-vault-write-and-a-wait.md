# 0010 — Rotation is a vault write and a wait

**Status:** Accepted

**Decided:** 2026-10-10

**Evidence:** PR #41, and the measurement recorded beside the secret in
[infra/modules/workload/main.tf](../../infra/modules/workload/main.tf)

## Context

Writing the runbook's rotation procedure meant checking it against Microsoft's current
documentation, which says that where a Key Vault URI carries no version the app retrieves the
latest version within 30 minutes, and that active revisions referencing it are restarted to pick
up the new value. This module's reference is versionless and the value is consumed as an
environment variable, so both halves apply here — against
[0009](0009-rotation-requires-a-deployment.md), which said the opposite.

## Options considered

**Keep 0009 and ignore the documentation.** It was, after all, proven twice on the live service.

**Take the documentation's word for it.** Cheap, and it would have left the repository asserting
something it had not seen.

**Measure it with a clock.**

## Decision

Measured on dev. The new value was written at 10:42:41Z and both keys were probed against
`POST /quote` every 150 seconds for 51 minutes. The old key worked at +23 minutes; at +25
minutes the old key returned 401 and the new one returned 200. Same revision name, same creation
time, one replica throughout. **A rotation is a vault write and a wait.**

## Consequences

The runbook's procedure is four steps and none of them produces a deployment. It does produce
two commits, in step one, and they are the other half of the story: adding the vault grant and
removing it again both touch `infra/bootstrap`, which `trigger.paths` excludes, so neither
fires a build. An operator following 0009 would have written the value, committed twice,
watched no build start, and concluded that the rotation had not taken.

**The cutover is hard.** The old key stopped being accepted inside the same 150-second window
the new one started working, so there is no grace period — anything holding the old value breaks
without warning, up to half an hour after the write.

A deployment is now the fast path rather than the only one, and that cuts both ways: deploying
inside the refresh window produces a genuinely mixed application, the new revision accepting the
new key while its neighbours still hold the old.

**Why 0009 was wrong is the part worth keeping.** Both of its observations were real. Both were
taken minutes after the write — inside the refresh window, where the platform has not fetched
the new version yet and a restart therefore re-injects the old value. Two confirmations of a
negative taken at the same moment relative to the change are one confirmation, and a mechanism
with a documented delay cannot be tested by a fast experiment. Nothing in the original recorded
*when* it was measured, which is what would have made the gap visible.
