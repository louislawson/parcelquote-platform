# Runbook

What to do when a production deployment goes wrong, and what not to reach for. Everything here is
about production unless it says otherwise — dev deploys on every commit to main and is not worth a
procedure.

This file is deliberately not an explanation.
[`.azuredevops/README.md`](../.azuredevops/README.md) describes how the pipeline works and why,
and [`infra/envs/prod/README.md`](../infra/envs/prod/README.md) describes the environment it
deploys to. Both are worth reading before you need this one; what follows assumes you have read
neither recently.

Resource names are written out literally rather than derived, because at the moment you need them
you should not have to work out what anything is called.

## Is production healthy?

Three questions, in the order worth asking them.

**What is serving, and under which label?**

```bash
az containerapp ingress show -n ca-parcelquote-prod-uks-01 -g rg-parcelquote-prod-uks-01 \
  --query traffic -o table
```

Two rows, `green` and `blue`. Either split is normal: `green 100 / blue 0` after a successful
deployment, `green 0 / blue 100` after a rollback or between a deployment's first two applies. The
labels are what tell you which revision is which — see **Green and blue never swap** below — and
the weights only tell you which one is being served.

**Is the resource itself in a good state?**

```bash
az containerapp show -n ca-parcelquote-prod-uks-01 -g rg-parcelquote-prod-uks-01 \
  --query "{state:properties.provisioningState, mode:properties.configuration.activeRevisionsMode}" -o tsv
```

Expect `Succeeded` and `Multiple`. `Failed` here does not mean production is down — the app keeps
serving the revision it already had — but it does mean the next write will be refused, which is
**Rolling back by hand** below. A mode other than `Multiple` is the problem described in **The
canary was skipped**.

**What is each hostname actually answering?**

```bash
FQDN=$(az containerapp ingress show -n ca-parcelquote-prod-uks-01 -g rg-parcelquote-prod-uks-01 \
  --query fqdn -o tsv)

for host in "$FQDN" "${FQDN/./---green.}" "${FQDN/./---blue.}"; do
  echo "$host $(curl -fsS --max-time 60 --retry 5 --retry-all-errors "https://$host/version")"
done
```

The retry flags are not optional. A revision holding no traffic has scaled to zero, and a cold
start here is 48 seconds, so one impatient `curl` looks exactly like a broken revision. The block
is bash — on Windows run it in Git Bash, since PowerShell cannot parse `${FQDN/./---green.}`.
Hostnames elided to their first label, this is the state a failed deployment left on
9 October 2026:

```text
ca-parcelquote-prod-uks-01            {"git_sha":"d13f64d"}
ca-parcelquote-prod-uks-01---green    {"git_sha":"435fd2f"}
ca-parcelquote-prod-uks-01---blue     {"git_sha":"d13f64d"}
```

Production on `d13f64d`, and the revision a rollback rejected still running and still reachable on
`---green`, serving nobody. That is the expected end state of a rollback, not a half-finished
deployment.

## A prod deploy failed

Find the step that failed in the run's timeline. Where it failed decides what production served
and whether anything needs doing.

| Step that failed | What production is serving | What to do |
| --- | --- | --- |
| The approval was never given | The previous commit. Prod never deployed | Re-run the build. A *timed out* approval marks the stage skipped and the build **green** |
| Discover the revision prod is serving | The previous commit. Nothing has been written | Read the error; there is nothing to undo |
| Apply prod with the candidate at 0% traffic | The previous commit | The rollback ran and re-applied the same target, which is harmless and misdescribed — see below |
| Verify the candidate while prod still serves the old revision | The previous commit | Nothing to undo. The new revision exists at 0% and is reachable on `---green`; debug it there |
| Shift 10% or 50% of traffic to the new revision | Whatever the last shift that *did* complete left — the previous commit, or the new revision at 10% | An apply failed rather than a check. The rollback returned traffic; confirm with **Is production healthy?** |
| Measure the split at 10% or at 50% | That share went to the new revision for the length of one apply | The rollback returned traffic. Confirm with **Is production healthy?** |
| Shift all traffic to the new revision | The new revision at 50%, since that shift did not complete | As above |
| Measure the split after the shift | Everything, briefly | As above |
| Roll back | **Possibly the new revision** | **Rolling back by hand**, below |
| Smoke test, Key Vault grant or alert receiver | **The new revision, at 100%** | No rollback happened: these run *after* the rollback step by design, since neither standing assertion says anything about this revision. A failing smoke test is the case for **Rolling back by hand** |
| Nothing failed, but the log says `staged rollout: false` | The new commit, deployed without a canary | **The canary was skipped**, below |

**The exposure, measured rather than estimated.** On the one run that exercised this deliberately,
the rejected revision held 10% of traffic for about a minute — ten requests, all of which
succeeded — between the shift and the rollback completing. A revision that fails verification at
0% serves nothing at all.

**One case reads worse than it is.** If the *staged apply itself* fails, the rollback applies the
configuration that apply was already attempting, under a step called "Roll back: return all
traffic to the previous revision". Production is never at risk; the log simply misdescribes what
happened.

**And one case where the rollback is meant not to run.** Each measurement warms both revisions
before sampling, so it is the only step that knows *which* of the two will not answer. If the
previous revision is the broken one, the rollback stands down and says so rather than routing all
of production at something already proven dead. Do not force it. Production is on the new
revision, and the thing to investigate is why the old one stopped answering.

## Rolling back by hand

Only needed when the automatic rollback did not run. Check the provisioning state first:

```bash
az containerapp show -n ca-parcelquote-prod-uks-01 -g rg-parcelquote-prod-uks-01 \
  --query properties.provisioningState -o tsv
```

**If that says `Failed`, the traffic change below will be refused as well.** A failed *template*
operation is kept as desired state and retried on every subsequent write, including one that
touches nothing but weights, and the error names a revision suffix that appears nowhere in the
resource — a `GET` reports the last suffix that succeeded. Recovery is template first, traffic
second: get a valid template applied by running the pipeline on a commit whose suffix has never
been used, and only then shift traffic. What puts the app in that state is in **What not to reach
for**.

With the state `Succeeded`, one command:

```bash
az containerapp ingress traffic set -n ca-parcelquote-prod-uks-01 -g rg-parcelquote-prod-uks-01 \
  --label-weight blue=100 green=0
```

It needs no revision name, which is most of what the labels are for, and it prints the resulting
split. Terraform's state is left stale on the weights, which is self-correcting: the next merge
applies its own, taking `green` for its candidate and finding the blue revision as the stable one
to hold the remainder.

Then confirm it with the hostname loop in **Is production healthy?** rather than with the
command's own output. `traffic set` prints the configuration it accepted, not evidence that the
revision now carrying production answers — and a rollback onto a revision that has broken since
looks identical in that output to one that worked.

## What not to reach for

**Re-queueing the previous good build.** It cannot work, and it leaves things worse than it found
them. A revision suffix is the short commit SHA, that suffix is spent for the life of the app, and
the platform rejects the deployment:

```text
Field 'template.revisionsuffix' is invalid with details: 'Invalid value: "v1a2b3c4":
revision with suffix v1a2b3c4 already exists.'
```

The apply fails, the rollback applies the same template and fails as well, and the app is left at
`provisioningState: Failed` — which then refuses the manual traffic shift above until a valid
template has been applied. Production keeps serving what it was serving throughout. Deactivating
the old revision does not release its suffix, so pruning revisions is not a way around this.

**Redeploying the old image tag** fails for the same reason. The rule is narrower than it first
looks and worth stating exactly: a reused suffix is rejected when the template differs from the
one currently running, because that is when the platform has to create a revision. A template
identical to what is already running creates nothing and is accepted, which is why prod's
permanent `template.revision_suffix` diff applies cleanly on every deploy. Redeploying an old tag
is the first case, not the second. A rollback here is a traffic shift or it is nothing.

**`terraform apply` from a laptop.** It works, and it defeats the approval that is the reason
production has its own directory. Local runs are for reading plans.

**`az containerapp revision restart` to pick up a new secret.** It replaces the container without
creating a revision, and a secret reference resolves only at revision creation — see **Rotating
production's API key**.

## Green and blue never swap

`green` is always the newest revision and `blue` is always the one it replaced. The weights say
which of them is serving. This is a deliberate departure from Microsoft's blue/green guidance,
which alternates the two roles each cycle and therefore has to record somewhere which colour is
currently production.

Two consequences worth knowing before they surprise you:

- Between a deployment's first two applies, production is on **blue**. That is the arrangement
  working, not a sign that something went wrong.
- After a failed deployment, `---green` keeps pointing at the **rejected** revision until the next
  deployment takes the label back. A green hostname answering with a stale SHA is expected.

## The canary was skipped

The symptom is in the "Discover the revision prod is serving" step: `staged rollout: false`, every
canary step skipped, and the build **green**.

Two causes are benign. A re-run of a commit that has already deployed finds its own revision
holding all the traffic, and correctly does nothing. An app with no previous revision at all has
nothing to hold traffic while a candidate is verified, so the candidate goes straight to 100%
under Azure's own readiness gate.

The third is not benign. If production has been switched out of `Multiple` revision mode, or the
previous revision has been deactivated, a deployment goes straight to 100% with no canary, no
measurement and no rollback available — and nothing fails. Check the mode and the revision list
with the commands in **Is production healthy?**. Terraform restores the mode on the next apply,
but the deployment that ran without a safety net had none, and the revision a rollback would have
needed may be gone.

## Rotating production's API key

Two facts shape this. Nobody holds data-plane access to production's vault. And the secret
reference is versionless, so the platform picks up a new version on its own — **measured at 23 to
25 minutes on dev**, inside the half hour Microsoft documents.

1. Write the new value. The grant to do it does not exist standing: add `prod` to
   `local.manual_secret_environments` in [`infra/bootstrap`](../infra/bootstrap/README.md), apply,
   write the secret with `-o none` so the value is not echoed back, remove `prod` from the list
   and apply again. Two commits, so the window is in the history rather than in someone's memory.
2. Wait. Every active revision that references the secret converges on the new version within
   about half an hour and is restarted in place to pick it up — no new revision, no deployment
   and no commit. `az containerapp revision restart` does not hurry it along: inside the window
   the platform has not fetched the new version yet, so a restart re-injects the old one, which
   is what made this look like a deployment-only operation for two phases.
3. Only deploy if it has to be live sooner. A revision resolves the latest version as it is
   created, so a deployment makes the new value live immediately. That is the one reason to
   involve the pipeline, and note that the trigger covers `app`, `infra` and `.azuredevops` but
   **excludes `infra/bootstrap`** — so the commits from step 1 fire no build by themselves.
4. The cutover is hard, not graceful. On dev the old key stopped being accepted in the same
   two-and-a-half-minute window the new one started working, so there is no overlap: anything
   still holding the old value breaks, without warning and up to half an hour after the write.
   The one period where both keys work is between the write and the refresh, and only for a
   revision created inside it — that revision resolves the new value at birth while its
   neighbours still hold the old one. Production runs several active revisions, so a deployment
   during the window puts the app in exactly that state.

## Revisions accumulate and nothing prunes them

```bash
az containerapp revision list -n ca-parcelquote-prod-uks-01 -g rg-parcelquote-prod-uks-01 \
  --query "length([?properties.active])" -o tsv
```

Six as of 10 October 2026, roughly one per merge. In `Multiple` mode nothing is deactivated unless
something deactivates it, and nothing does. They cost nothing — billing follows replicas and an
idle revision has none — so the only real limit is Azure's ceiling of 100 revisions, after which
the oldest is purged. Nothing watches the count, which is why it is worth a look rather than a
trust.

Deactivating an old revision by hand is safe, with two exceptions: not whichever revision is
carrying traffic, and not the one `blue` points at, because that is the rollback target. It does
not free the suffix either.

## Things that look like failures and are not

- **A pull request with no checks at all** means the pipeline YAML failed validation. A pull
  request that the path filters exclude posts a visible `skipping` check, so an absent check is
  diagnostic rather than merely suspicious. The reason is only in the build's `validationResults`
  field, at `_apis/build/builds/<id>`, and the timeline is empty.
- **A build that dies in zero seconds** is the same thing.
- **A service connection that will not verify.** Expected, and correct — see
  [`.azuredevops/README.md`](../.azuredevops/README.md), which also explains why granting it
  subscription Reader to make the check pass is the wrong fix.
- **A run that pauses asking for permission** on first use of a service connection, environment or
  variable group. Once per protected resource.
- **`StatusCode = 0` with a duration around 25,000 ms** in the logs is a caller that gave up
  during a cold start, not a server error.
- **A plan that changes `latest_revision_name` or `latest_revision_fqdn` with no resource change.**
  The provider reads both one revision stale immediately after an apply. Nothing automated should
  assert against either.
- **A SaaS gate failing on a tool error.** Both Snyk tasks fail closed deliberately; check
  <https://status.snyk.io> and <https://sonarcloud.statuspage.io> before inferring an outage from
  build history.

## What this platform does not have

The canary proves that traffic weighting works and that the new revision answers correctly at each
step. It does not prove the revision is healthy under load, because there is no load: this service
sees a couple of requests an hour, and the alerts that might gate a soak run on fifteen-minute
windows. The observation is synthetic, and the honest claim is about the mechanism rather than the
evidence.

Nobody is paged. Alerts email one address and nothing escalates. A deployment that fails at 02:00
rolls itself back and waits to be read in the morning, which is the right trade for a reference
implementation and would be the wrong one for a service with users.

The rollback covers a bad revision. It does nothing about a bad infrastructure change, which is
what the plan published on every run is for.
