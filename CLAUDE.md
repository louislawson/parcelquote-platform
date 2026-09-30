# parcelquote-platform

A reference implementation of a secretless Azure delivery pipeline. The application is
deliberately small; the platform around it is the point.

This file holds what the READMEs do not: the conventions, the local equivalents of the
pipeline gates, and the few rules that are easy to break by accident. It deliberately does
not summarise the documentation — the READMEs are the documentation, and a copy here would
only give the two something to drift apart over.

## Read before changing anything

| File | What it answers |
| ---- | --------------- |
| [`README.md`](README.md) | What the project is, the stack, and which phases are done |
| [`app/README.md`](app/README.md) | The pricing model, the API and its authentication, local development |
| [`infra/bootstrap/README.md`](infra/bootstrap/README.md) | The foundational resources, why it runs by hand, what permissions it needs |
| [`infra/envs/dev/README.md`](infra/envs/dev/README.md) | The dev environment, what it reads rather than creates, and its constraints |
| [`.azuredevops/README.md`](.azuredevops/README.md) | The pipeline, and the configuration that lives in Azure DevOps rather than here |

Each infrastructure README ends with a **Gotchas** section. Read it before editing that
configuration; it exists because someone already lost time to what it records.

## How changes are made

The repository owner writes the code. An agent explains the stage before it is built and
reviews what comes back — it does not write the change unasked. Write code when asked
directly, or when a short snippet is the clearest way to explain something.

Work proceeds through the phases listed in the root README, one at a time, and each is
briefed before it starts. Do not begin the next phase until asked.

When a change spans the application and the infrastructure, land the infrastructure first.
Every merge to `main` deploys and then smoke tests the running revision, so an application
change that depends on infrastructure not yet applied turns `main` red.

Branches are `feat/`, `fix/`, `docs/` or `chore/` followed by a short description, and commit
subjects use the same prefixes. One logical change per pull request.

## Conventions

**Comments record decisions, not behaviour.** This is the repository's most distinctive habit
and the easiest one to break. A comment that restates the code — `# create the key vault` —
is worse than no comment. The ones here explain why a value was chosen, what a
plausible-looking alternative would have cost, or what breaks when someone later
"simplifies" the line. They are allowed to run to several sentences. Where a decision has no
interesting reason behind it, leave it uncommented rather than padding.

**One hundred characters.** Python (`ruff`, `line-length = 100`), Markdown
(`.markdownlint.json`, with tables and code blocks exempt) and Terraform comments all wrap at
100.

**Azure resource names are interpolated, never literal.** The pattern is
`<abbreviation>-<project>-<environment or purpose>-<location_short>-01`, built from variables
so a name cannot disagree with the variable that is supposed to produce it. Storage accounts
and the container registry drop the hyphens, and Key Vault drops the `-01` because vault
names cap at 24 characters. Terraform resource labels are snake_case and mirror the
abbreviation: `rg_dev`, `st_tfstate`, `cr_shared`, `ca_dev`.

**Every resource carries `merge(local.common_tags, { environment = ... })`.**

**A grant that should reach some environments and not others filters on an explicit
allow-list local** — `image_build_environment`, `deployment_environments`,
`manual_secret_environments` — rather than on the environment map itself. Adding an
environment somewhere else must not silently widen a privilege here.

**The Inputs and Outputs tables in the infrastructure READMEs are generated.** They sit
between `<!-- BEGIN_TF_DOCS -->` and `<!-- END_TF_DOCS -->` and come from terraform-docs.
Change `variables.tf` or `outputs.tf` and regenerate; do not hand-edit the table.

**Add to a Gotchas list, never replace an entry.** Two separate edits have quietly deleted an
existing gotcha by writing a new one over it. Only the diff catches this, so read it.

## Checks

The pipeline runs these; run them before pushing. From the repository root:

```bash
terraform fmt -check -diff -recursive infra
```

Per configuration, for each of `infra/bootstrap` and `infra/envs/dev`:

```bash
terraform -chdir=infra/envs/dev init -backend=false -input=false && terraform -chdir=infra/envs/dev validate
```

`validate` is weaker than it looks. It catches a dangling resource reference, but not an
attribute lookup on `each.value` when `for_each` iterates a collection of resources, because
the type is unknown until plan. Plan is the real gate for that class of error, and the
pipeline's validate stage will wave it through.

Checkov, pinned to the version the pipeline installs:

```bash
checkov -d infra --framework terraform --compact
```

A suppression is `#checkov:skip=CKV_...:<reason>` where the reason states the decision that
was made and why. Name a phase only when the work genuinely is deferred to it; a skip that
points at a phase nobody has committed to is a decision in disguise. Read a check's source
before suppressing it — its title is not a reliable description of what it tests.

From `app/`:

```bash
poetry run ruff check .
```

```bash
poetry run pytest
```

## Rules

- **Never commit anything from `planning/`.** It is gitignored: local notes, not for
  publication.
- **Never print a secret or an access token.** `az keyvault secret set` echoes the value it
  has just written, so always pass `-o none`. Generate secret values inline so they do not
  reach shell history, and never write one to a tfvars file, a `.env` or a commit.
- **A binary `tfplan` never leaves the agent.** It contains resolved state, including
  workspace shared keys. `*tfplan*` is gitignored, and the pipeline publishes only the text
  output of `terraform show`.
- **Pull request builds must not touch Azure.** The repository is public and forks can open
  pull requests. Anything needing the service connection belongs in a stage gated on
  `refs/heads/main`.
- **Do not add a credential to make something work.** The registry's admin account and
  anonymous pull are both disabled; authentication is Entra ID and federated identity. The
  two third-party gates hold API tokens because neither vendor offers federation, and that
  exception is documented rather than repeated.
