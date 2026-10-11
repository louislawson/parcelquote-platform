# 0007 — Documentation builds on a pull request and deploys nothing

**Status:** Accepted

**Decided:** 2026-10-11

**Evidence:** PR #46, which merged with no build at all, and the `pr` trigger this record
changes

## Context

PR 43 added two documentation gates to the validate stage: every generated table must match the
configuration it describes, and every relative link in the tracked Markdown must resolve. PR 45
then made them report independently.

PR #46 added a 237-line architecture document and two diagrams, and **neither gate ran**. Both
trigger blocks named `app`, `infra` and `.azuredevops`, so the Azure Pipelines check reported
*skipping* and no build existed. The repository had acquired checks whose subject is
documentation and a trigger that excluded documentation. Running the loops by hand before
committing is the only reason that was not a hole.

## Options considered

**Leave it.** The gates exist for files they will never see. A documentation-only change is then
reviewed and not checked, which is the state the repository was in before PR 43 — reintroduced
one layer up.

**Widen both triggers.** A documentation commit on `main` would then build an image tagged with
its commit SHA, create a production revision, **spend a revision suffix for the life of the
app** (see [0001](0001-container-apps-as-the-runtime.md)), run a four-step canary over an
application that did not change, and ask a human to approve it. A typo fix would cost a
deployment.

**Widen both, and condition the deploy stages on whether a deployable path changed.** Correct in
principle and real machinery: a variable computed from a diff, consumed by three stage
conditions. A condition that silently skips a deployment is a worse failure than the one being
fixed, and this phase has already found two checks that reported nothing while the build went
green.

**A second pipeline for documentation.** Workable, and it adds a ninth piece of configuration
living in Azure DevOps rather than in this repository, plus a second place for the steps to
drift unless they are extracted into a template first.

## Decision

Widen the `pr` trigger only, to `docs`, `README.md` and `CLAUDE.md`. The two trigger blocks
answer different questions — **the pull request trigger decides what gets checked, and the CI
trigger decides what gets deployed** — and documentation belongs in the first and not in the
second.

## Consequences

A documentation-only pull request now runs the full validate stage, so the documentation gates
and the decision-log check see the files they were written for.

It is not free: that stage also runs the tests, the quality gate and both Snyk scans over an
application that did not change, costing a few agent-minutes per documentation pull request and
a Sonar analysis that will report exactly what the last one did.

It also gives a documentation pull request a way to fail that has nothing to do with it. The
validate stage builds the image and runs both Snyk scans, which fail closed on findings and on
tool errors alike ([0006](0006-gates-fail-closed.md)), so a newly disclosed vulnerability in the
base image — or a vendor outage like the one on 6 October 2026 — now blocks a typo fix. Before
this change, documentation could not be blocked at all. That is the cost most likely to be felt,
and the answer when it happens is the one already written for any gate outage in
[.azuredevops/README.md](../../.azuredevops/README.md): wait, or fix what the gate found.

A documentation-only merge to `main` still builds nothing. The consequence is worth stating
plainly: documentation on `main` was checked on the pull request that introduced it and is never
checked again, so a change merged by any route that skips a pull request is unchecked. There is
no such route today.

And the root-level files are named one by one because Azure DevOps path filters are prefix
matches with no wildcard support. A new Markdown file added at the repository root is not
covered until somebody adds it here — which is exactly the kind of silent gap this record exists
to close, reintroduced one level further down.
