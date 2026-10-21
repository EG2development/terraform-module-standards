# terraform-module-standards

The standard for this organisation's Terraform module repositories, and everything
needed to apply it without thinking about it twice:

| What | Where |
| --- | --- |
| The standard: naming, layout, branching (feature → dev → main), Conventional Commits, versioning, release-please, consumption, CI, versions, security, CODEOWNERS, rulesets, merge strategy, dependency updates, README, template | [`docs/standard.md`](docs/standard.md) |
| Runbooks: create a repository, daily workflow, release, breaking change, migrate an existing module, upgrade a consumer, troubleshooting, decision records | [`docs/runbooks/`](docs/runbooks/README.md) |
| The workflows every module runs (`workflow.yml`, `release-please.yml`) and the instructions Copilot code review follows for decision records | In each module repository's `.github/`, copied from `terraform-aws-module-template`. Nothing here is called at run time |
| Rulesets for `dev`, `main` and release tags | [`rulesets/`](rulesets/) |
| Create and configure a module repository in one command | [`scripts/new-module-repo.sh`](scripts/new-module-repo.sh) |
| Check a module repository against the standard | [`scripts/check-module-repo.sh`](scripts/check-module-repo.sh) |

The template that new module repositories are created from is the separate repository
`terraform-aws-module-template`.

## Create the tenth module repository exactly like the first

```bash
scripts/new-module-repo.sh --owner EG2development --name ecr-repository --team platform-engineering --visibility public
cd terraform-aws-ecr-repository
# add main.tf, variables.tf, outputs.tf, examples/basic, tests; then
gh pr create --title "feat: add the ecr-repository module" --body "...

Release-As: 1.0.0"
```

Merge it, merge the release pull request release-please opens, and `v1.0.0` exists.
Full procedure: [create-repository.md](docs/runbooks/create-repository.md).

## How a change becomes a release

```text
branch → pull request into dev (Conventional Commit title) → Static Analysis → review → squash merge
dev    → scripts/promote.sh opens "chore(promote): dev to main" → Static Analysis → human approval → squash merge
main   → release-please updates "chore(main): release X.Y.Z" → merge it → tag vX.Y.Z + GitHub Release
main   → merged back into dev by a pull request after each release
```

## Changing the standard

Open a pull request here for the standard, the rulesets, the runbooks or the scripts.
Workflows are not shared: a change to CI, to the release workflow or to the
decision-record automation is made in `terraform-aws-module-template` and rolled out to
each module repository by pull request, so every repository keeps running on its own.
This repository still runs `actionlint`, `shellcheck` and ruleset validation on every
pull request.
