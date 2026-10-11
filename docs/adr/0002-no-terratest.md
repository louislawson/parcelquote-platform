# 0002 — No Terratest; static analysis and a smoke test instead

**Status:** Accepted

**Decided:** 2026-08-30

**Evidence:** the absence of any Go in this repository, and the validate stage of
[.azuredevops/azure-pipelines.yml](../../.azuredevops/azure-pipelines.yml)

## Context

Infrastructure code needs verifying, and Terratest is the reach most people make. The question
was what would actually catch the failures this repository produces, at a size where the whole
infrastructure is one module and two root configurations.

## Options considered

**Terratest.** Provisions real infrastructure and asserts against it, in Go. That is a second
language in a Python repository, minutes of runtime per test, and real Azure spend on every run
— for a configuration whose resources are already created and destroyed by the pipeline on every
merge. The tests would exercise what the deploy exercises anyway.

**Terraform's native test framework.** Available since 1.6 and cheap to run since mock providers
arrived in 1.7, both of them years old by the time this was scoped and both available in the
1.16 these configurations require. This is the option with no convenient excuse. It asserts well
on logic — a module that computes, validates or branches — and this module mostly passes values
through to a provider, so most assertions would restate the configuration and then break
whenever the configuration changed, which is maintenance in exchange for nothing. The one place
it would earn its keep is the generated resource names, where a length or character-set
assertion would catch what tflint provably misses; that gap is open and recorded rather than
closed by this decision.

**Static analysis plus an end-to-end assertion on the deployed thing.**

## Decision

`terraform fmt`, `validate` and tflint on every configuration, Checkov for policy, and a smoke
test that asks the running revision which commit it is. The real gate is the plan published on
every apply plus the assertions that run after it.

## Consequences

It catches the class of error that actually occurs here — policy regressions, formatting,
dangling references, a stale generated table — at no cost and in seconds.

It does not catch the class `validate` is blind to, and that blindness is specific enough to
write down: an attribute lookup on `each.value` where `for_each` iterates a collection of
resources is unknown until plan, so validate waves it through. [CLAUDE.md](../../CLAUDE.md) says
so beside the command. The deploy-time assertions cover some of the rest — the Key Vault grant
and the alert receiver are checked on every deploy precisely because no static tool can see them.

The honest cost is that nothing verifies the module in isolation. Both callers are in this
repository and both are deployed on every merge, so a break is caught in dev before production
sees it; the day this module acquires a caller that is not deployed on every merge, this record
is the first one to revisit.
