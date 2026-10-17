# Create a module repository

## Purpose

Create `terraform-aws-<name>` from the template, apply the standard, land the module
code and release `v1.0.0`. Section 0 is done once per organisation; everything after
it is the same for the first repository and the tenth.

## Prerequisites

- `gh` signed in with the `repo`, `read:org` and `admin:org` scopes
  (`gh auth refresh -s admin:org`), and permission to create repositories in the
  organisation.
- `jq`, `perl`, `git`, Terraform 1.9 or later, `tflint`, `terraform-docs`.
- A clone of `terraform-module-standards`.

```bash
OWNER=EG2development          # organisation that hosts the repositories
TEAM=platform-engineering     # team that owns the modules
NAME=ecr-repository           # the capability; the repository is terraform-aws-$NAME
VISIBILITY=public             # public or private; see step 0.1
STANDARDS=~/terraform-module-standards
```

## Steps

### 0. Once per organisation

Skip this section if `${OWNER}/terraform-module-standards` already exists.

#### 0.1 Decide visibility and plan

| Organisation plan | Repository visibility | Rulesets, CODEOWNERS, required checks |
| --- | --- | --- |
| Free | Public | Enforced |
| Free | Private | **Not available.** GitHub refuses the rulesets, so nothing is enforced |
| Team or Enterprise | Either | Enforced |

```bash
gh api "orgs/${OWNER}" --jq '.plan.name'
```

On the Free plan choose public repositories for modules that pass the readiness
checklist (they contain no project knowledge by definition), or move the organisation
to GitHub Team. Decide once; mixed visibility means two sets of rules.

#### 0.2 Create the owning team

```bash
gh api "orgs/${OWNER}/teams/${TEAM}" > /dev/null 2>&1 \
  || gh api -X POST "orgs/${OWNER}/teams" -f "name=${TEAM}" -f privacy=closed
```

#### 0.3 Publish the standards repository

```bash
cd "${STANDARDS}"
perl -pi -e "s/__OWNER__/${OWNER}/g; s/__TEAM__/${TEAM}/g" .github/CODEOWNERS
git init -b main 2> /dev/null || true
git add .github .markdownlint-cli2.jsonc .gitignore .pre-commit-config.yaml LICENSE README.md docs rulesets scripts
git status --short
git commit -m "feat: terraform module repository standard"
gh repo create "${OWNER}/terraform-module-standards" "--${VISIBILITY}" --source . --push \
  --description "Standard, runbooks, reusable workflows and rulesets for Terraform module repositories"
gh repo edit "${OWNER}/terraform-module-standards" --enable-squash-merge --enable-merge-commit=false \
  --enable-rebase-merge=false --delete-branch-on-merge --allow-update-branch \
  --squash-merge-commit-message pr-title-description
# Let other repositories call the reusable workflows (needed only when private).
[ "${VISIBILITY}" = "private" ] && gh api -X PUT "repos/${OWNER}/terraform-module-standards/actions/permissions/access" -f access_level=organization
# Let Dependabot in the module repositories resolve those workflows (needed only when
# private; without it every module's Dependabot run fails with git_dependencies_not_reachable).
[ "${VISIBILITY}" = "private" ] && jq -n --argjson id "$(gh api "repos/${OWNER}/terraform-module-standards" --jq .id)" \
  '{repository_ids_to_add: [$id]}' | gh api -X PATCH "orgs/${OWNER}/dependabot/repository-access" --input -
for f in rulesets/main.json rulesets/release-tags.json; do
  gh api -X POST "repos/${OWNER}/terraform-module-standards/rulesets" --input "$f" > /dev/null && echo "applied $f"
done
```

#### 0.4 Publish the template repository

```bash
cd ~/terraform-aws-module-template
grep -rlI --exclude-dir=.git -e __OWNER__ -e __TEAM__ . | xargs perl -pi -e "s/__OWNER__/${OWNER}/g; s/__TEAM__/${TEAM}/g"
terraform fmt -check -recursive && terraform init -backend=false > /dev/null && terraform validate && terraform test
git init -b main 2> /dev/null || true
git add .github .gitignore .pre-commit-config.yaml .release-please-manifest.json .terraform-docs.yml .tflint.hcl \
  CHANGELOG.md CONTRIBUTING.md LICENSE README.md main.tf outputs.tf release-please-config.json variables.tf versions.tf examples tests
git status --short
git commit -m "feat: terraform module repository template"
gh repo create "${OWNER}/terraform-aws-module-template" "--${VISIBILITY}" --source . --push \
  --description "Template for terraform-aws-* module repositories"
gh repo edit "${OWNER}/terraform-aws-module-template" --template
```

#### 0.5 Create the two GitHub Apps

In **Organisation settings → Developer settings → GitHub Apps → New GitHub App**:

| App | Permissions | Installed on | Used by |
| --- | --- | --- | --- |
| `terraform-release-bot` | Repository: Contents read/write, Pull requests read/write, Issues read/write. Webhook: off | All `terraform-aws-*` repositories | `terraform-release.yml` to open release pull requests that trigger CI |
| `terraform-modules-reader` | Repository: Contents read-only. Webhook: off | All `terraform-aws-*` repositories | Consuming repositories' CI, to `terraform init` private modules |

For each App, note the **Client ID** and generate a **private key**. Store them where
every module repository can read them:

```bash
# Organisation secrets (private repositories need GitHub Team or above for this).
gh secret set RELEASE_APP_CLIENT_ID   --org "${OWNER}" --visibility all --body "<client id>"
gh secret set RELEASE_APP_PRIVATE_KEY --org "${OWNER}" --visibility all < terraform-release-bot.private-key.pem
```

If organisation secrets are not available, pass `--release-app-client-id` and
`--release-app-key-file` to the bootstrap script in step 1 instead, every time.

Consuming repositories store the reader App's values as `MODULES_APP_CLIENT_ID`
(variable) and `MODULES_APP_PRIVATE_KEY` (secret); see
[upgrade-module-version.md](upgrade-module-version.md).

### 1. Create the repository

```bash
cd ~/src   # wherever you keep clones
"${STANDARDS}/scripts/new-module-repo.sh" --owner "${OWNER}" --name "${NAME}" --team "${TEAM}" \
  --visibility "${VISIBILITY}" --description "Terraform module for one Amazon ECR repository with secure defaults"
```

The script creates the repository from the template, grants the team maintain access,
replaces the placeholders, pushes that one commit, creates the `dev` branch from it and
makes it the default branch, sets squash-only merging, enables Dependabot, secret
scanning and immutable releases, adds topics and imports the three rulesets. Re-running
it is safe.

### 2. Check the empty repository

```bash
gh repo view "${OWNER}/terraform-aws-${NAME}" --json name,visibility,isTemplate,repositoryTopics
gh api "repos/${OWNER}/terraform-aws-${NAME}/branches/dev" --jq .name                      # expect dev
gh api "repos/${OWNER}/terraform-aws-${NAME}" --jq .default_branch                         # expect dev
gh api "repos/${OWNER}/terraform-aws-${NAME}/rulesets" --jq '.[] | "\(.target)\t\(.name)\t\(.enforcement)"'
gh api "repos/${OWNER}/terraform-aws-${NAME}/codeowners/errors" --jq '.errors | length'   # expect 0
```

### 3. Add the module code

```bash
cd "terraform-aws-${NAME}"
git switch dev && git switch -c feat/initial-module
```

Replace the placeholder content of `main.tf`, `variables.tf`, `outputs.tf`,
`examples/basic/` and `tests/`. Keep `versions.tf` to minimums only. Write the README
sections 1, 2, 6 and 7 from [the standard, section 15](../standard.md#15-module-readme).
Then:

```bash
terraform fmt -recursive
terraform init -backend=false && terraform validate
for d in examples/*/; do terraform -chdir="$d" init -backend=false > /dev/null && terraform -chdir="$d" validate; done
terraform test
tflint --init && tflint --recursive
terraform-docs .                       # regenerates the tables in README.md
checkov -d . --framework terraform --quiet
"${STANDARDS}/scripts/check-module-repo.sh" .
```

### 4. Open the first pull request

```bash
git add main.tf variables.tf outputs.tf versions.tf README.md examples tests
git status --short
git commit -m "feat: add the ${NAME} module"
git push -u origin feat/initial-module
gh pr create --base dev --title "feat: add the ${NAME} module" --body "$(cat <<'BODY'
## What changed

First version of the module.

## How it was checked

terraform test, tflint, checkov and terraform-docs pass locally; CI runs the same.

Release-As: 1.0.0
BODY
)"
```

The last line of the description is what makes the first release `1.0.0` instead of
`0.1.0`. Keep it as the last line; the promotion script carries it to `main`.

### 5. Merge into dev, then promote

Wait for `ci / CI passed` and one approval from `@${OWNER}/${TEAM}`, then squash merge
from the pull request page or with `gh pr merge --squash`. Then open the promotion:

```bash
"${STANDARDS}/scripts/promote.sh" --dry-run     # the description must end with "Release-As: 1.0.0"
"${STANDARDS}/scripts/promote.sh"
```

A human approves `chore(promote): dev to main` and squash merges it
([promote-to-main.md](promote-to-main.md)).

### 6. Release 1.0.0

Within a minute of the promotion, release-please opens `chore(main): release 1.0.0`.

```bash
gh pr list --label "autorelease: pending"
```

Review it: `CHANGELOG.md` has a `1.0.0` section, the README usage line says
`?ref=v1.0.0`, the manifest says `"1.0.0"`. Merge it. release-please then creates the
tag and the GitHub Release. Full detail: [release.md](release.md).

### 7. Point consumers at it

[upgrade-module-version.md](upgrade-module-version.md) for a new consumer;
[migrate-existing-module.md](migrate-existing-module.md) when the module replaces a
copy inside a project.

## Validation

```bash
"${STANDARDS}/scripts/check-module-repo.sh" . --repo "${OWNER}/terraform-aws-${NAME}"
gh release view v1.0.0 --repo "${OWNER}/terraform-aws-${NAME}"
git ls-remote --tags origin 'v*'
```

All checks `PASS`; the release exists; exactly one tag.

## Rollback

- Repository created with the wrong name or visibility, nothing released yet: rename
  with `gh repo rename`, or delete with `gh repo delete` (needs the `delete_repo`
  scope) and start again.
- A release with a mistake: tags are immutable. Fix forward with a `fix:` pull request
  and let release-please cut the patch release.

## Troubleshooting

See [troubleshooting.md](troubleshooting.md): "release-please opened 0.1.0", "the
release pull request has no checks", "creating a ruleset fails".
