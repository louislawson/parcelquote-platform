# 0012 — One workload module, called twice

**Status:** Accepted

**Decided:** 2026-10-06

**Evidence:** PR #30, and build 50's published plan

## Context

Production had to exist, and the thing to avoid was two environments differing by copy-paste.
[0011](0011-a-module-per-resource-type.md) had an answer ready; building it was the first time
anyone checked whether that answer survived contact with what had actually been built.

## Options considered

**0011's five resource modules.** Three of them turned out to be already elsewhere or not worth
having, for two different reasons. The registry is shared by every environment, so a module
instantiated per environment cannot own it. The vault is per-environment but still belongs to
bootstrap, because the app identity's grant on it is a role assignment and a pipeline identity
cannot write one. And a naming module would add an indirection that cannot
validate anything the interpolated names do not already guarantee. Splitting the remaining two
would mean threading the workspace id, the app's FQDN and the action group out of one module and
into another, when nothing will ever instantiate one without the other.

**Copy-paste between environments, with discipline.** The failure this phase exists to avoid.

**One pattern module, called once per environment.** In Azure Verified Modules terms a pattern
module rather than a resource module: it composes several resources to serve a recognised
architecture, and may be any size.

## Decision

One module, `infra/modules/workload`, called by both environments, differing in the values they
pass and the state they own.

The argument that settled it is narrower than the general case for small modules: **module
boundaries buy flexibility for callers you do not control.** This module has two callers, both
in this repository.

## Consequences

Dev was refactored into it while running. That is a state move against live resources, and the
evidence that it was clean is build 50's plan: nothing added, nothing destroyed, one change,
and that change the image tag every merge carries.

Inside the module, resource labels drop the environment — `ca`, not `ca_dev` — because a label
naming one environment is wrong for the other. Tags arrive as a finished map rather than being
built, since the `source` tag names the configuration that owns the resource and only the root
knows that.

**The claim that production needed no change to the module is narrower than it sounds**, and
worth stating precisely because the root README got it wrong once. Prod came into existence
without changing the module; the three traffic-shifting inputs were added to it afterwards, for
production's benefit. One module with two callers means prod-only behaviour has nowhere to live
except the shared interface.
