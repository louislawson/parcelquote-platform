# 0017 — Automated dependency and base image updates, declined

**Status:** Accepted

**Decided:** 2026-10-07

**Evidence:** PR #33, which introduced the pinned-versions table in
[.azuredevops/README.md](../../.azuredevops/README.md), and the base image comment in
[app/Dockerfile](../../app/Dockerfile)

## Context

Six versions are pinned — Terraform, tflint, Checkov, the Snyk CLI, terraform-docs and the base
image digest — and nothing updates any of them. Pinning the base image by digest makes every
fixable operating system finding a bump task by construction, and that task has no owner except
a human who remembers.

## Options considered

**Dependabot.** It has no Azure Pipelines ecosystem and no generic manager, so it cannot see
five of the six. Worse, on a `FROM` line carrying a digest without a tag it resolves the digest
of `latest`, so it would propose a Python interpreter migration and label it a security update.

**Renovate.** It can reach all six through custom regex managers, which is both why it is the
right tool and what it costs: five hand-written regexes that fail silently when they stop
matching, in a repository whose standing complaint about gates is that the dangerous failure is
the quiet one.

**Neither, with the gap written down.**

## Decision

Neither. The pinned-versions table names each version, where it lives and the exact command to
bump it, and that table is the whole mechanism.

## Consequences

Five of the six have nothing watching them. They fail by under-checking rather than by failing,
so a stale pin is invisible until somebody looks, and "somebody looks" is not a schedule.

The base image is the exception, and it shows what the others lack: Snyk's container gate
catches a digest that has gone stale, which is how the `perl-base` advisories surfaced within
about 36 hours of publication.

This is the record most likely to be revisited, and the confidence behind it is moderate rather
than high. The argument against Renovate is a judgement about maintenance cost rather than a
defect in the tool, and the first pinned version to go a year without a bump is the evidence
that the judgement was wrong.
