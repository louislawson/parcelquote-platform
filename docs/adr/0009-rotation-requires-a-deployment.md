# 0009 — Rotating the key requires a deployment

**Status:** Superseded by [0010](0010-rotation-is-a-vault-write-and-a-wait.md)

**Decided:** 2026-09-28

**Evidence:** the comment PR #20 wrote into `infra/envs/dev/main.tf`, carried into the module by
PR #30 and corrected by PR #41

## Context

[0008](0008-the-api-key-lives-in-key-vault.md) chose a versionless Key Vault reference, which
leaves one question open: when a new version of the secret is written, when does the running
application start using it? The answer determines what an operator has to do to rotate a key,
and therefore what the runbook tells them.

## Options considered

**Read the platform documentation.** Not done. The behaviour looked like something that could be
established directly.

**Measure it on the live service.** Done, twice: a new value was written to the vault and the
old key kept working, and a revision was restarted and the old key kept working after that too.

## Decision

A rotation takes effect on the next revision. Changing the key therefore means producing a
deployment, and the operator procedure says so.

## Consequences

The configuration says so where it matters: the comment beside the secret reference tells the
next reader that a rotation needs no change there but takes effect only on the next revision.
Any operator procedure written from it will tell someone to produce a deployment.

Confidence is high. The claim was not inferred from documentation but proven twice against the
running service, by two different routes, and both observations agreed.

The cost is carried by whoever rotates the key: a routine credential change becomes a code
change, a build and a deployment, with everything that implies for an environment behind a
manual approval.
