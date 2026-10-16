# Upgrade a module version in a consuming repository

## Purpose

Move a root configuration from `?ref=vA.B.C` to `?ref=vX.Y.Z` safely.

## Prerequisites

- Credentials to `terraform init` and `plan` the root configuration.
- Read access to the module repository (public, or the reader App set up in step 0).

```bash
OWNER=EG2development
REPO=terraform-aws-ecr-repository
NEW=v1.3.0
```

## Steps

### 0. Once per consuming repository: read access and Dependabot

If the module repository is private, every machine that runs `terraform init` needs
read access. Workstations: `gh auth setup-git` (HTTPS) or an SSH key. GitHub Actions:
store the reader App's client ID as the variable `MODULES_APP_CLIENT_ID` and its
private key as the secret `MODULES_APP_PRIVATE_KEY`, then add before `terraform init`:

```yaml
- uses: actions/create-github-app-token@bcd2ba49218906704ab6c1aa796996da409d3eb1 # v3.2.0
  id: modules-token
  with:
    client-id: ${{ vars.MODULES_APP_CLIENT_ID }}
    private-key: ${{ secrets.MODULES_APP_PRIVATE_KEY }}
    owner: OWNER
    repositories: terraform-aws-ecr-repository
    permission-contents: read

- name: Let Git read the module repositories
  env:
    TOKEN: ${{ steps.modules-token.outputs.token }}
  run: git config --global url."https://x-access-token:${TOKEN}@github.com/OWNER/".insteadOf "https://github.com/OWNER/"
```

Let Dependabot open upgrade pull requests. In `.github/dependabot.yml`:

```yaml
  - package-ecosystem: terraform
    directory: /infra/deploy/aws        # each root that calls modules
    schedule:
      interval: weekly
    commit-message:
      prefix: "chore(deps)"
```

Dependabot treats `?ref=vX.Y.Z` as a version and bumps it when a new tag appears.

### 1. Read the changelog

```bash
gh release view "${NEW}" --repo "${OWNER}/${REPO}"
```

Read every release between yours and `${NEW}`. A major release lists what you must
change under ⚠ BREAKING CHANGES and in the README's Upgrading section.

### 2. Change the pin

Edit the `source` (or accept the Dependabot pull request). Make any argument changes
the changelog asked for.

### 3. Re-initialise and plan

```bash
terraform init -upgrade -backend-config=<backend>
WORK="$(mktemp -d)"
terraform plan -var-file=<tfvars> -out="$WORK/upgrade.tfplan"
terraform show -json "$WORK/upgrade.tfplan" | jq -r '.resource_changes[] | select(.change.actions != ["no-op"]) | "\(.change.actions | join(",")) \(.address)"'
```

Terraform downloads module code only during `init`; without it, `plan` stops with
`Module source has changed`.

### 4. Judge the plan

| Release | Expected plan |
| --- | --- |
| Patch or minor | No changes, unless you opted into something new |
| Major | Exactly the changes the changelog described. Nothing `delete`d or replaced that it did not mention |

### 5. Merge and apply

Through the root configuration's normal review and apply process.

## Validation

After apply, `terraform plan` shows no changes, and
`jq -r '.Modules[] | select(.Key != "") | "\(.Key)\t\(.Source)"' .terraform/modules/modules.json`
lists the new `ref`.

## Rollback

Set `?ref=` back to the previous tag, `terraform init -upgrade`, `terraform plan`. If
the new version was already applied and changed resources, that plan reverses them;
review it like any other plan.

## Troubleshooting

| Symptom | Cause | Fix |
| --- | --- | --- |
| `Module source has changed` | `init` not re-run | `terraform init -upgrade` |
| `Failed to download module` with `could not read Username` or `Permission denied (publickey)` | No read access | Step 0 |
| `Failed to download module` and the source has `depth=1` with a SHA | Shallow clones take branch and tag names only | Remove `depth=1` |
| Dependabot opens no pull request | `terraform` ecosystem missing, or the directory is wrong | Step 0; the `directory` must be the root that contains the `module` block |
