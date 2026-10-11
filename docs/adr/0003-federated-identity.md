# 0003 — Federated identity, and no stored Azure credential

**Status:** Superseded by [0099](0099-does-not-exist.md)

**Decided:** 2026-09-02

**Evidence:** PR #1, and the service connections described in
[.azuredevops/README.md](../../.azuredevops/README.md)

## Context

A pipeline that provisions Azure has to authenticate to Azure, and the default path is a service
principal with a client secret pasted into a service connection. A secretless delivery pipeline
was the subject of the project rather than a nice-to-have, so the authentication mechanism was
the first thing that had to be right. Whatever was chosen would be load-bearing for everything
after it.

## Options considered

**A client secret in the service connection.** Works immediately, expires on a date nobody
remembers, has to be rotated by hand, and exists as a string that can be pasted somewhere else.
Every later claim about secrets in this repository would have had an asterisk on it.

**A certificate.** The same custody problem in a different file format.

**A managed identity on a self-hosted agent.** Genuinely secretless, and it requires an agent
machine: a VM to run, patch and pay for, which contradicts the cost constraint and adds the one
piece of long-lived infrastructure the design was trying to avoid.

**Workload identity federation.** Azure DevOps presents an OIDC token identifying the service
connection; Entra trusts that subject on a specific app registration and issues a real token.
Nothing is stored at either end.

## Decision

Workload identity federation, one app registration per environment, each holding Contributor on
that environment's resource group and data access to that environment's state container and
nothing else.

## Consequences

There is nothing to rotate and nothing to leak, and the claim survives inspection rather than
needing to be taken on trust — a reader can look at the service connections and see no secret.

**Contributor excludes writing role assignments**, so a pipeline identity cannot widen its own
access. That is the property worth having, and it has a cost that propagates through the whole
design: every grant in the platform must be created by something else, which is why bootstrap
exists and is applied by hand, and why the rebuild in
[docs/architecture.md](../architecture.md) interleaves rather than running from code. See
[0004](0004-remote-state-and-the-bootstrap-seam.md).

Two gates could not follow this rule. SonarQube Cloud and Snyk offer no federation, so they hold
expiring personal access tokens — the one exception, documented rather than quietly tolerated,
and the reason fork builds are disabled rather than merely gated. See
[0006](0006-gates-fail-closed.md).

And federation carries a dated maintenance item that a stored secret would not have: the
federated credential issuer changes, with the old one retiring on 1 July 2027. Production is on
the current issuer; dev predates it and has not been checked. A mechanism with no expiry still
has a deadline.
