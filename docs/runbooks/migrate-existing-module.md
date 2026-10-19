# Migrate an existing module to its own repository

## Purpose

Move a module from inside a project repository (for example
`infra/modules/aws/<module>`) into `terraform-aws-<name>`, switch the project to the
released version, and prove that no infrastructure changes because of it.

```text
Identify module → Check dependencies → Create repository → Copy module → Add repo standards
→ Run validation → Create initial release → Update module consumers → terraform init -upgrade
→ terraform plan → Confirm no unintended change → Merge → Remove old copy
```

## Prerequisites

- Everything in [create-repository.md](create-repository.md), including section 0.
- Read access to the project's Terraform state and the credentials to plan it, for
  every environment that has state.
- The module passes the readiness checklist below. If it does not, fix the module
  **inside the project first**, as its own pull request, and plan that change on its own.

```bash
OWNER=EG2development
TEAM=platform-engineering
NAME=ecr-repository                    # new repository: terraform-aws-$NAME
PROJECT=~/ALXnderia                    # the project that holds the module today
OLD=infra/modules/aws/registry         # path of the module inside the project
ROOT=infra/deploy/aws                  # root configuration that calls it
STANDARDS=~/terraform-module-standards
```

## Steps

### 1. Identify the module and check its dependencies

```bash
cd "${PROJECT}"
git grep -n "source *= *\"[./]*${OLD#infra/}\"" -- '*.tf'          # every caller
git grep -nE 'path\.module\}?/\.\.|path\.(root|cwd)' -- "${OLD}/*.tf"  # reads outside its directory
git grep -nE '^\s*(provider|backend)\s+"' -- "${OLD}/*.tf"          # provider or backend blocks
git grep -niE 'alxnderia|eu-west|[0-9]{12}' -- "${OLD}/*.tf"        # project names, regions, account IDs
```

Readiness checklist. Every line must hold before you continue:

- [ ] No `provider` or `backend` block.
- [ ] Nothing read from outside the module directory.
- [ ] No project name, account ID, region, address range, secret or CI identity
      hard-coded. Each is an input.
- [ ] No knowledge of the application (environment variable names, schema paths,
      database roles).
- [ ] No account-wide singleton (a setting that exists once per account).
- [ ] Secure defaults; inputs that weaken them are named for what they weaken.
- [ ] You know every caller and every output other modules consume.

Record the interface map: old input name → new input name, old resource address →
new resource address. The goal is **identical addresses**; where that is impossible,
the module ships `moved` blocks (step 4).

### 2. Create the repository

```bash
"${STANDARDS}/scripts/new-module-repo.sh" --owner "${OWNER}" --name "${NAME}" --team "${TEAM}" --visibility public
cd "terraform-aws-${NAME}" && git switch -c feat/initial-module
```

### 3. Copy the module

```bash
cp "${PROJECT}/${OLD}"/*.tf .
```

Then make it general:

- Remove project tags and names from the code; take them as inputs (`tags`, `name`).
- Replace project enumerations (`environment` must be `dev|stage|prod`) with plain
  strings or drop them.
- Add `validation` blocks, `nullable = false`, descriptions.
- Set `versions.tf` to the family's Terraform floor (`>= 1.16.0`) and the real
  provider minimum (`aws >= 6.0` unless the code needs more, with a comment saying
  what).
- **Keep every resource type and name** (`aws_ecr_repository.main` stays `main`)
  where the resource stays in the module. Where a resource gains `count` or leaves
  the module, the consumer writes the `moved` block in its own root configuration —
  root `moved` blocks may move state into and within Git-sourced modules. Never put
  a consumer's history in the shared module.
- Drive `count`/`for_each` from `bool` inputs, never from a null check on a value that
  may be unknown at plan time.

### 4. Add the repository standards

Fill `examples/basic/`, `tests/` (defaults, inputs, validation, examples) and the
README sections. Where a default policy or document is generated, add a test that
compares it **byte for byte** with what the old module produced, so a drift fails the
test rather than the consumer's plan.

### 5. Run the validation

```bash
terraform fmt -recursive && terraform init -backend=false && terraform validate
for d in examples/*/; do terraform -chdir="$d" init -backend=false > /dev/null && terraform -chdir="$d" validate; done
terraform test && tflint --init && tflint --recursive && terraform-docs . && checkov -d . --framework terraform --quiet
"${STANDARDS}/scripts/check-module-repo.sh" .
```

### 6. Create the initial release

Open the pull request with `Release-As: 1.0.0` as the last line of the description,
merge, merge the release pull request ([create-repository.md](create-repository.md),
steps 4–6). Note the commit SHA of `v1.0.0` for consumers that must pin SHAs:

```bash
git fetch --tags && git rev-parse 'v1.0.0^{commit}'
```

### 7. Update the consumers

In the project, on a branch, change every caller's `source` and arguments according to
the interface map. Keep the **module call name** (`module.registry`) exactly as it is;
it is part of every resource address.

```hcl
module "registry" {
  source = "git::https://github.com/OWNER/terraform-aws-ecr-repository.git?ref=v1.0.0"

  name                 = var.project_name
  force_delete         = var.ecr_force_delete
  image_tag_mutability = var.ecr_image_tag_mutability

  # The old module added these tags itself; passing them keeps the plan empty.
  tags = {
    Project   = var.project_name
    ManagedBy = "terraform"
  }
}
```

In the same pull request:

- If pre-commit runs TFLint with `--call-module-type=all`, change it to `local`;
  remote modules are linted in their own repository.
- If the project's CI runs `terraform init` and the module repository is private, add
  the reader App token step before `init`
  ([upgrade-module-version.md](upgrade-module-version.md), step 0).
- Add the `terraform` ecosystem to the project's `dependabot.yml` for the new source.

Do not delete `${OLD}` yet. It is the rollback path.

### 8. Re-initialise

```bash
cd "${PROJECT}/${ROOT}"
terraform init -upgrade -backend-config=<your backend config>
terraform validate
```

`init` prints one line per call:
`Downloading git::https://github.com/${OWNER}/terraform-aws-${NAME}.git?ref=v1.0.0`.

### 9. Plan, and compare with the plan before the change

For **every environment with state**:

```bash
WORK="$(mktemp -d)"
VARS=<path to the environment's tfvars>
summarise() { terraform show -json "$1" | jq -r '.resource_changes[] | select(.change.actions != ["no-op"]) | "\(.change.actions | join(",")) \(.address)"' | sort; }

git switch main && terraform init -upgrade -backend-config=<backend> > /dev/null
terraform plan -var-file="$VARS" -out="$WORK/before.tfplan" > /dev/null && summarise "$WORK/before.tfplan" > "$WORK/before.txt"

git switch <your-branch> && terraform init -upgrade -backend-config=<backend> > /dev/null
terraform plan -var-file="$VARS" -out="$WORK/after.tfplan" > /dev/null && summarise "$WORK/after.tfplan" > "$WORK/after.txt"

diff "$WORK/before.txt" "$WORK/after.txt" && echo "PASS: the migration adds no change"
grep -E " module\.(registry|ingestion_registry)\." "$WORK/after.txt" || echo "PASS: migrated resources untouched"
terraform show -json "$WORK/after.tfplan" | jq -r '.resource_changes[] | select(.change.actions | index("delete")) | .address'   # must print nothing new
```

Plan files can contain secrets; `$WORK` is outside the repository. Delete it after.

### 10. Confirm no unintended change

Both `PASS` lines, and nothing deleted or replaced that the "before" plan did not
already contain. If a migrated resource shows an **update**, an input no longer
matches (most often tags); fix the inputs, never the state. If it shows a **replace**,
stop: a name or an immutable attribute differs.

### 11. Merge

Terraform state records addresses, not where module code came from. A no-change plan
means the migration is complete when the pull request merges. There is nothing to
apply.

### 12. Remove the old copy

After one release cycle without a rollback: delete `${OLD}` in its own pull request
and update any catalogue the project keeps.

## Validation

- Step 9 passes in every environment with state.
- `${STANDARDS}/scripts/check-module-repo.sh . --repo ${OWNER}/terraform-aws-${NAME}` passes.
- The project's CI is green with the Git source.

## Rollback

Revert the consumer pull request, `terraform init -upgrade`, plan: with unchanged
addresses this is also a no-change plan. This works only while `${OLD}` still exists,
which is why it is deleted last.

## Troubleshooting

| Symptom | Cause | Fix |
| --- | --- | --- |
| Plan replaces every resource of the module | The module call was renamed, or `count`/`for_each` was added to the call | Keep the call name; or add root-level `moved { from = module.old to = module.new }` |
| Plan replaces one resource | The resource was renamed inside the module without a `moved` block, or an immutable argument differs | Add the `moved` block in the module (major release) or fix the input |
| Plan updates tags in place | The old module added tags the new one does not | Pass them through `tags` |
| `terraform init` fails with a Git authentication error | Private repository, no credentials on this machine or runner | `gh auth setup-git` locally; reader App token in CI |
| TFLint: `module is not found. Did you run "terraform init"?` | `--call-module-type=all` | Use `local` |
| `Invalid count argument` | `count` depends on a value unknown at plan time | Drive it from a `bool` input |
