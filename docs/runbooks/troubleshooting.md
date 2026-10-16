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
| The ruleset waits for `ci / CI passed` and it never appears | The caller job in `ci.yml` is not called `ci`, or the shared workflow's final job was renamed | The caller job id must be `ci` and have no `name:`; the check name is `<caller job> / <called job name>` |
| `PR title` fails | Title is not `type(scope)!: description` with an allowed type | Retitle. Types: `feat fix docs chore refactor test ci revert` |
| `Docs` fails with a diff | README tables are stale | `terraform-docs .`, commit `README.md` |
| `Test (Terraform <minimum>)` fails, `latest` passes | A feature newer than `required_version` | Avoid it, or raise the minimum in a `feat!:` pull request and raise `terraform-min-version` in `ci.yml` |
| `Lint`: `Failed to install a plugin` or rate limit | TFLint could not download the AWS ruleset | The shared workflow passes `GITHUB_TOKEN`; locally set `GITHUB_TOKEN=$(gh auth token)` |
| `Security scan` fails on a check you accept | Checkov finding | Add the ID to `checkov-skip-checks` in `ci.yml` **and** justify it in the README under Security scanning |
| Every job fails within seconds with no steps | Actions billing or quota for the owner, not the code | Run the checks locally; fix billing; re-run |
| `terraform test`: `Unsupported block type mock_provider` | Terraform older than 1.7 | Upgrade Terraform |
| `Invalid count argument` | `count` depends on a value unknown at plan time | Drive it from a `bool` input |

### release-please

| Symptom | Cause | Fix |
| --- | --- | --- |
| No release pull request after a merge | No `feat`/`fix`/breaking commit since the last tag, or the squash title is not a Conventional Commit | `git log --oneline $(git describe --tags --abbrev=0)..main`; merge an empty `fix:` pull request describing the change |
| First release pull request says `0.1.0` | The `terraform-module` strategy starts at 0.1.0 and the `Release-As: 1.0.0` footer was missing or not last | Merge a small `fix:` pull request whose description ends with `Release-As: 1.0.0` |
| Release pull request has no checks, cannot merge | release-please ran as `GITHUB_TOKEN`; pull requests it opens never trigger workflows | `gh secret list --repo ${OWNER}/${REPO}` must show `RELEASE_APP_CLIENT_ID` and `RELEASE_APP_PRIVATE_KEY`, as repository or organisation secrets |
| Release workflow: `Resource not accessible by integration` | The App lacks Contents, Pull requests or Issues write | Add the permission on the App, accept it on the installation, re-run |
| README `version = "~> 1.0"` appeared or a provider pin in the README changed | The `terraform-module` strategy rewrites the first `version = "~> X.Y"` in `README.md` | Never write `~>` constraints in the README. Use `>=` in prose and tables |
| `versions.tf` changed in the release pull request | The strategy rewrites every `vX.Y.Z` string in `versions.tf` | Remove the string (comments included); `check-module-repo.sh` flags it |
| Breaking change released as minor | `!` missing from the title and no `BREAKING CHANGE:` footer, or the repository merges with "pull request title" only | Set the squash default to title + description (`new-module-repo.sh --configure-only`); add `Release-As: N.0.0` in a follow-up |
| Extra, unexpected changelog entries | Lines in the pull-request description that look like `fix: ...` are parsed as commits | Write descriptions in prose; edit the release pull-request description to remove them |
| Tag created but no GitHub Release | Workflow interrupted | Re-run the release workflow; it is idempotent |

### Repository settings

| Symptom | Cause | Fix |
| --- | --- | --- |
| Rulesets imported, but direct pushes to `main` still work | Private repository on GitHub Free: rulesets are not enforced | Make the repository public or move the organisation to GitHub Team; `gh api repos/${OWNER}/${REPO}/rules/branches/main` lists what is in effect |
| CODEOWNERS review is never requested | Team has no write access, or the team name is wrong | `gh api repos/${OWNER}/${REPO}/codeowners/errors`; grant the team maintain access |
| `gh api ... --input rulesets/main.json` returns 422 | A read-only field (`id`, `source`) in the JSON, or a ruleset with that name already exists | Use the files from `terraform-module-standards/rulesets/`; the script updates an existing ruleset by name |
| Reusable workflow: `workflow was not found` or `is not accessible` | The standards repository is private and not shared with the organisation, or the plan does not allow it | `gh api -X PUT repos/${OWNER}/terraform-module-standards/actions/permissions/access -f access_level=organization`; or make it public |

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
