# Troubleshooting

## Purpose

Symptoms seen in module repositories, their cause, and the fix. Check here before
changing a workflow.

## Prerequisites

`gh` signed in; the repository cloned.

```bash
OWNER=EG2development
REPO=terraform-aws-ecr-repository
```

## Steps

Find your symptom. Each row names where the fix lives.

### CI

| Symptom | Cause | Fix |
| --- | --- | --- |
| `PR title` fails | Title is not `type(scope)!: description` with an allowed type | Retitle. Types: `feat fix docs chore refactor test ci revert` |
| `Docs` fails with a diff | README tables are stale | `terraform-docs .`, commit `README.md` |
| `Test (Terraform <minimum>)` fails, `latest` passes | A feature newer than `required_version` | Avoid it, or raise the minimum in a `feat!:` pull request and raise the first `matrix.terraform` entry in `workflow.yml` |
| `tflint`: `Failed to install a plugin` or rate limit | TFLint could not download the AWS ruleset named in `.tflint.hcl` | Re-run the job; locally set `GITHUB_TOKEN=$(gh auth token)` |
| `checkov` fails on a check you accept | Checkov finding | Add the ID to `skip-check` in `configs/checkov.yml` **and** justify it in the README under Security scanning |
| Every job fails within seconds with no steps | Actions billing or quota for the owner, not the code | Run the checks locally; fix billing; re-run |
| `terraform init`: `Unsupported Terraform Core version` | Terraform older than 1.16, the floor of every module | Upgrade Terraform to 1.16 or later |
| `Invalid count argument` | `count` depends on a value unknown at plan time | Drive it from a `bool` input |

### release-please

| Symptom | Cause | Fix |
| --- | --- | --- |
| No release pull request after a merge | No `feat`/`fix`/breaking commit since the last tag, or the squash title is not a Conventional Commit | `git log --oneline $(git describe --tags --abbrev=0)..main`; merge an empty `fix:` pull request describing the change |
| First release pull request says `0.1.0` | The `terraform-module` strategy starts at 0.1.0 and the `Release-As: 1.0.0` footer was missing or not last | Merge a small `fix:` pull request whose description ends with `Release-As: 1.0.0` |
| Release pull request shows no checks | Expected: release-please runs as `GITHUB_TOKEN`, and pull requests it opens start no workflows | Review and merge; no check is required |
| Release workflow: `Resource not accessible by integration` | The release job lacks contents or pull-requests write | Keep the `permissions` block in `release-please.yml`; check no organisation policy caps it. If it fails while labelling the release pull request, add `issues: write` |
| Release workflow: `GitHub Actions is not permitted to create or approve pull requests` | The repository or organisation setting is off | `gh api -X PUT repos/${OWNER}/${REPO}/actions/permissions/workflow -F can_approve_pull_request_reviews=true`, or tick it under Settings → Actions → General |
| README `version = "~> 1.0"` appeared or a provider pin in the README changed | The `terraform-module` strategy rewrites the first `version = "~> X.Y"` in `README.md` | Never write `~>` constraints in the README. Use `>=` in prose and tables |
| `versions.tf` changed in the release pull request | The strategy rewrites every `vX.Y.Z` string in `versions.tf` | Remove the string (comments included); `check-module-repo.sh` flags it |
| Breaking change released as minor | `!` missing from the title and no `BREAKING CHANGE:` footer, or the repository merges with "pull request title" only | Set the squash default to title + description (`new-module-repo.sh --configure-only`); add `Release-As: N.0.0` in a follow-up |
| Extra, unexpected changelog entries | Lines in the pull-request description that look like `fix: ...` are parsed as commits | Write descriptions in prose; edit the release pull-request description to remove them |
| Tag created but no GitHub Release | Workflow interrupted | Re-run the release workflow; it is idempotent |
| A change merged into `dev` is missing from the release pull request, or the bump is too small | The promotion was merged with a merge commit (release-please reads `main` in commit-date order and stops at the last release), or a header line in its description was bulleted or indented | Edit the merged promotion's description: `BEGIN_COMMIT_OVERRIDE` … `END_COMMIT_OVERRIDE` with one header per line at column 0; rerun the release workflow. Squash merge promotions, always |
| `promote.sh`: `dev does not contain main` | `main` has not been merged back into `dev` since the last release | Open a pull request from `main` into `dev`; an admin allows merge commits in the repository settings, merges it with a merge commit (a squash would not make `main` part of `dev`'s history), and turns merge commits off again |
| The `main` → `dev` pull request conflicts | A pull request into `dev` changed a line release-please also rewrites (the README usage pin, `CHANGELOG.md`) | Resolve the conflict in that pull request; an admin merges it with a merge commit; keep release-please-owned lines untouched on `dev` |

### Repository settings

| Symptom | Cause | Fix |
| --- | --- | --- |
| Dependabot fails with `git_dependencies_not_reachable` for `terraform-module-standards` | The standards repository is private and not in the organisation's Dependabot access list | Add it: [create-repository.md](create-repository.md), step 0.3; `gh api orgs/${OWNER}/dependabot/repository-access` lists what Dependabot can read |
| Creating a ruleset fails with "Upgrade to GitHub Pro or make this repository public to enable this feature" | Private repository on GitHub Free: rulesets are not available | Make the repository public or move the organisation to GitHub Team; `gh api repos/${OWNER}/${REPO}/rules/branches/main` lists what is in effect |
| CODEOWNERS review is never requested | Team has no write access, or the team name is wrong | `gh api repos/${OWNER}/${REPO}/codeowners/errors`; grant the team maintain access |
| `gh api ... --input rulesets/main.json` returns 422 | A read-only field (`id`, `source`) in the JSON, or a ruleset with that name already exists | Use the files from `terraform-module-standards/rulesets/`; the script updates an existing ruleset by name |

### Consumers

| Symptom | Cause | Fix |
| --- | --- | --- |
| `terraform init`: `Failed to download module`, `could not read Username` | No read access to a private module repository | `gh auth setup-git`; reader App token in CI ([upgrade-module-version.md](upgrade-module-version.md), step 0) |
| `Module source has changed` | `init` not re-run after changing `source` | `terraform init -upgrade` |
| TFLint: `module is not found. Did you run "terraform init"?` | `--call-module-type=all` with a Git-sourced module | Use `--call-module-type=local` |
| Checkov in the consumer stops reporting the module's resources | Expected; Checkov scans only the code in that repository | Nothing: the module repository scans them |

## Validation

After any fix, re-run `scripts/check-module-repo.sh . --repo ${OWNER}/${REPO}` from the
standards repository and re-run the failed workflow.

## Rollback

Settings changes made with `new-module-repo.sh --configure-only` are idempotent and
can be re-applied after any manual change.

## Troubleshooting

If the symptom is not here, open an issue in `terraform-module-standards` with the
workflow run URL. Add the row to this page when it is solved.
