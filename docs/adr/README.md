# Decision log

Why this platform is shaped the way it is, one decision per file. The READMEs describe what is
true now and [docs/architecture.md](../architecture.md) describes how the pieces fit; these
records describe what was chosen, when, against what alternatives, and what it cost.

Every record here was written after the fact, in October 2026, for decisions made from August
onwards. That is the normal case for a workload that already exists rather than a defect —
Microsoft's guidance is explicit that a record "should be started for brownfield workloads, and
if the data is available, it should be retroactively generated based on known past decisions" —
but it does mean each one could quietly become a justification for what happened instead of an
account of what was chosen. Three things guard against that, and they are the conventions worth
keeping:

- **`Decided` is the date the decision was made**, taken from the merge commit, not the date the
  record was written.
- **`Evidence` names a pull request, a build or a file**, so every claim here can be checked
  against something outside this directory.
- **At least one consequence is a cost actually paid.** A record with nothing but benefits in its
  consequences has been written backwards from the outcome. The first two of these are checkable
  against something outside this directory and the build checks part of them; this one is a
  review standard, and no gate has an opinion about it.

## How a record works

It is **append-only**. An accepted record is never edited to reflect a change of mind: a decision
that changes gets a new record that supersedes the old one, and both stay. That is what makes
these files safe to add to a repository that gates its documentation — a record cannot drift,
because it never claimed to be current. It claims to describe a moment.

`Status` is one of three things, and nothing else:

| Status | Meaning |
| --- | --- |
| `Proposed` | Written, not yet settled. Rare here; most of these were settled before they were written |
| `Accepted` | In force |
| `Superseded by` and a link | Replaced. The link is required, and it must resolve |

Neither this file nor the template writes that status out in full, which is itself worth
knowing: the link check reads every Markdown file in the repository, code spans and fenced
blocks included, so an illustrative link has to point at something real. The gate's error
message carries the exact shape instead.

**A superseding pair lands in one commit.** A record cannot point forward at a successor that does
not exist yet, so the old record and the new one are written together — which also forces the
author to state the change honestly in both directions.

Numbers are allocation order, not chronological order. They are identity, nothing more; the
`Decided` column below is what makes this read as a history. Start from
[template.md](template.md).

The validate stage checks the shape of every record: that it has a row below whose link matches
its filename, that its number is unique, that it has the four sections and the three metadata
lines, that a superseding status names a record that exists, and that the date and status in
that row agree with the record itself. The table repeats what the records say, so something has
to hold the two together. What no gate can check is whether a record is honest.

## What is deliberately not recorded

The scope rule is Microsoft's: only choices that "affect the system's structure, key quality
attributes, or are difficult to reverse". Applied honestly, roughly forty decisions become
sixteen. Four kinds of thing are left out on purpose, so that their absence is a decision rather
than an oversight:

- **Why this project exists.** It has a purpose that is not technical, it is recorded outside this
  repository, and publishing it would turn a platform into a pitch.
- **Naming, tagging and label conventions.** [CLAUDE.md](../../CLAUDE.md) holds them; they are
  enforced by review, not by architecture.
- **Individual values** — thresholds, retention windows, sizes. They live beside the resource,
  where a generated table or a Gotchas entry keeps them honest. The decision to *measure* a
  threshold rather than choose one is recorded; the number is not.
- **Open questions.** A record for something undecided is a to-do list with a template. The
  subscription id's deliberate absence from this repository is the closest call and stays a
  Gotchas entry in [infra/envs/dev/README.md](../../infra/envs/dev/README.md): it is a
  configuration convention, not a structural choice, and it is reversible in an afternoon.

## The log

| # | Decision | Decided | Status |
| --- | --- | --- | --- |
| [0001](0001-container-apps-as-the-runtime.md) | Azure Container Apps as the runtime | 2026-08-30 | Accepted |
| [0002](0002-no-terratest.md) | No Terratest; static analysis and a smoke test instead | 2026-08-30 | Accepted |
| [0003](0003-federated-identity.md) | Federated identity, and no stored Azure credential | 2026-09-02 | Accepted |
| [0004](0004-remote-state-and-the-bootstrap-seam.md) | Remote state in Azure Storage, and a bootstrap applied by hand | 2026-09-03 | Accepted |
| [0005](0005-public-repository.md) | A public repository, and the stage split that follows from it | 2026-08-30 | Accepted |
| [0006](0006-gates-fail-closed.md) | Gates fail closed, and two of them hold tokens | 2026-09-27 | Proposed |
| [0007](0007-documentation-builds-on-a-pull-request.md) | Documentation builds on a pull request and deploys nothing | 2026-10-11 | Accepted |
