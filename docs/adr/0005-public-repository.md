# 0005 — A public repository, and the stage split that follows from it

**Status:** Accepted

**Decided:** 2026-08-30

**Evidence:** the design of 2026-08-30 for the repository being public, and PR #6 seventeen days
later, which introduced both the `pr` trigger and the `refs/heads/main` conditions that enforce
it

## Context

The repository is public, and that is deliberate: the work is meant to be readable by people who
are not given access to it first. Public means anyone can fork it, and a fork can open a pull
request, which means a pull request build runs code that nobody here reviewed before it ran.

Azure DevOps has settings for this, but a setting is a property of a project rather than of the
pipeline, and the pipeline is the thing in this repository.

## Options considered

**A private repository.** Removes the problem and most of the reason for building in the open.

**Public, with pull request builds holding the Azure service connection.** This is the default
shape of most pipelines, and it means a fork's pull request can run arbitrary code in a job
holding a credential to the subscription. Azure DevOps will not pass secrets to fork builds by
default, which makes this *probably* safe — and "probably safe, by a setting I did not write" is
not the property this project is demonstrating.

**Public, with fork builds disabled and nothing else.** A setting again, invisible from the
repository, and one wrong click from being untrue.

## Decision

Everything that needs Azure is gated on `refs/heads/main`, so a pull request build cannot reach
the subscription whether or not it comes from a fork. Fork builds are also disabled, as a second
line rather than the first.

## Consequences

This is why the pipeline has the shape it has: validate runs on every pull request and holds no
Azure credential, and publish, deploy-to-dev and deploy-to-prod exist only on `main`. A reader
can see the property in the YAML rather than having to be told about a project setting.

It also shaped how everything since has been *proven*. A change to the deployment path cannot be
demonstrated on a pull request, because the stages that would demonstrate it do not run there —
so the canary, the rollback and the mode guard were all exercised by merging and watching a real
build, and the pull requests that deliberately broke a gate had to be merged or closed rather
than simply opened.

The exception is honest and is the price: validate does hold two credentials, the SonarQube
Cloud and Snyk tokens, because those gates run there. They reach their own vendors and no Azure
resource, and disabling fork builds is what keeps a fork from reaching them. See
[0006](0006-gates-fail-closed.md).
