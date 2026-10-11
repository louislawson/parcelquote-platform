# 0006 — Gates fail closed, and two of them hold tokens

**Status:** Accepted

**Decided:** 2026-09-27

**Evidence:** PR #15 and PR #16, and build 23 on the closed PR #17

## Context

Phase 3 added a quality gate, dependency and image scanning, and Terraform policy checks. A gate
that reports a finding and lets the build through is a dashboard, not a gate, and the decision
was whether these would be able to stop a merge — including when the tool itself fails rather
than finding something.

## Options considered

**Warning-only.** Everything reports, nothing blocks, a human decides. In a repository with one
contributor this is indistinguishable from no gate at all.

**Fail closed, with a skip variable** for the day something must ship while a gate is
unreachable. Rejected for a specific reason: a variable is the same bypass with less of a trace.
The point of a fail-closed gate is that going around it leaves a record.

**Fail closed, including on tool errors.** A gate that passes when it could not evaluate
manufactures confidence, which is worse than one that fails loudly.

## Decision

All of them fail closed, on findings and on tool errors alike. There is no skip variable:
shipping past a gate means editing the pipeline, shipping, and reverting — three commits, all in
the history.

## Consequences

A vendor outage stops the build. That is not hypothetical: a Snyk incident on 6 October 2026
failed two consecutive builds about eight minutes apart, and the same commit passed unchanged the
next morning. Two retries absorb a bad response; they do not absorb an outage, and the runbook
for that is to wait, because nothing here has an SLA.

Two of the gates hold credentials, which is the single exception to
[0003](0003-federated-identity.md). Neither SonarQube Cloud nor Snyk offers federation, and the
project-scoped token alternatives are paid features on both platforms, so both connections carry
a personal access token belonging to an organisation owner. The exposure is recorded with its
expiry dates rather than left to be discovered.

**The proof is partial, and saying so is part of the decision.** Build 23 deliberately broke two
gates at once: Checkov failed on a removed suppression and the Snyk dependency scan failed on a
pinned vulnerable package, while everything unrelated passed. In that same run Sonar passed and
the image scan was skipped by its `succeeded()` condition — so two of the four gates have been
watched failing and two have only ever been watched passing. The image scan at least shares its
failure mechanism with the dependency scan that did fail. The quality gate shares nothing with
anything, and remains the gate taken most on trust.
