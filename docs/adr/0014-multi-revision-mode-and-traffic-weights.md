# 0014 — Multi-revision mode, weights in Terraform, and the commit SHA as the suffix

**Status:** Accepted

**Decided:** 2026-10-08

**Evidence:** PR #36, PR #38 and PR #39, and the four plans a production deployment publishes,
with a fifth when the rollback runs

## Context

Production had to be reversible: a bad release undone in seconds, without rebuilding anything,
and without the undo being a procedure somebody has to remember correctly at the worst possible
moment.

## Options considered

**Single revision mode, rolling back by redeploying the previous image tag.** The obvious
approach, and it does not work here. The revision suffix is the short commit SHA and a suffix
cannot be reused, so redeploying the old tag is refused by the platform — worth recording as a
rejected option precisely because it is what an operator will reach for first. See
[0001](0001-container-apps-as-the-runtime.md).

**Multi-revision mode with traffic set outside Terraform**, using
`az containerapp ingress traffic set --label-weight`. This is what Microsoft's own blue/green
guidance does. It puts the weights outside the configuration that owns the app, so the next
apply fights whatever the last command set, and the repository's claim that everything is in
code acquires its exception at the most interesting point.

**Multi-revision mode with the weights as module inputs.**

## Decision

Production runs in `Multiple` mode with the outgoing revision left running, the candidate's
share of traffic and the stable revision's suffix as inputs, and a `green` label giving the
candidate a hostname of its own so that it can be verified while holding no traffic.

## Consequences

A rollback is one apply: seconds, no rebuild, and it has been watched working rather than
written. The outgoing revision is still there because nothing deactivated it.

**A suffix is spent for the life of the app**, so a template change arriving without a new
commit cannot be applied at all.

**Production can never plan zero changes.** In `Multiple` mode the API does not return
`template.revisionSuffix`, so the provider reads it as empty and every plan proposes setting it.
Applying is a no-op. The consequence is for the reader rather than the operator: `1 to change`
in a production plan is the floor and not a signal, and the question to ask of a published plan
is *what* changed rather than how much.

Keeping the outgoing revision running is also what makes them accumulate, one per release
against the platform ceiling [0001](0001-container-apps-as-the-runtime.md) records.

And Terraform owning the weights means the pipeline applies the same configuration four times
per release and a fifth on failure, which is why that apply lives in a template rather than
inline.
