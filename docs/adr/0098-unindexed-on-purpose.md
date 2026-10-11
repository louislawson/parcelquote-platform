# 0098 — A record that is deliberately missing from the index

**Status:** Accepted

**Decided:** 2026-10-11

**Evidence:** this file, which exists only to fail a build

## Context

The decision-log check was proven in eight scenarios against a scratch copy of the tree, and
never on a hosted agent. Phase 3 set the standard that a gate is watched failing before it is
trusted, because a check that reports a problem and exits 0 looks exactly like a check that
found nothing — which is what PR 43's generated-table step did until PR 44 broke it on purpose.

## Options considered

**Trust the local runs.** They exercise the same script, extracted verbatim from the parsed
YAML, so the logic is the same. What they cannot show is that the step fails the build, that it
runs on the agent at all, or that it reports independently of the check above it.

**Break the gate on a branch and watch it.** Costs one pull request that is never merged, and
produces a build log that can be pointed at.

## Decision

This file is one of three deliberate breaks on a branch that will be closed unmerged. It is a
well-formed record with no row in the index, which is the failure a reviewer is least likely to
notice by eye: nothing about this file looks wrong on its own.

## Consequences

The branch carries content that must never reach `main`, which is a real risk and the reason
the pull request says so in its title. The cost is one pull request of noise in the history of a
repository that otherwise merges everything it opens.
