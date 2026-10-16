# Ship a breaking change

## Purpose

Release a new major version without surprising anyone: consumers learn what changes,
how to migrate, and get it in one place.

## Prerequisites

- You know the change is breaking: an input or output removed or renamed, a default
  that changes existing resources, a resource renamed, a replacement forced, or a
  higher minimum Terraform or provider version ([the standard, section 5](../standard.md#5-versioning)).

```bash
OWNER=EG2development
REPO=terraform-aws-ecr-repository
```

## Steps

### 1. Find who is affected

```bash
gh search code "${REPO}.git?ref=" --owner "${OWNER}" --json repository,path --jq '.[] | "\(.repository.nameWithOwner)\t\(.path)"'
```

List the consuming repositories in the pull-request description.

### 2. Write the migration before the code

In `README.md`, under **Upgrading**, add a section `### To vN.0.0` that says, per
change: what was removed or renamed, what to put in its place, and what the plan will
show. If a resource is renamed, add the `moved` block to the module so consumers see
"has moved" rather than "must be replaced":

```hcl
moved {
  from = aws_ecr_repository.main
  to   = aws_ecr_repository.this
}
```

Keep every `moved` block in all later releases; removing one is itself breaking.

### 3. Update the examples and tests

Every example must use the new interface. A test that asserted the old default now
asserts the new one, and the test file comment says why.

### 4. Open the pull request

Title with `!`, footer in the body:

```text
feat!: rename repository_name to name

Callers rename the argument; no resource changes.

BREAKING CHANGE: the input repository_name is now name. See README, Upgrading, To v2.0.0.
```

### 5. Merge, then release

CI and review as usual. release-please opens `chore(main): release N.0.0` with a
⚠ BREAKING CHANGES section. Confirm the major bump, then merge
([release.md](release.md)).

### 6. Open the consumer pull requests

For each repository from step 1, follow
[upgrade-module-version.md](upgrade-module-version.md); the plan review there is the
real test of your migration notes.

## Validation

- The release pull request title says `release N.0.0`, not `N-1.x.y`.
- `CHANGELOG.md` has the breaking entry with the migration pointer.
- Each consumer's plan after upgrading shows exactly what the README said it would.

## Rollback

Before merge: fix the pull request. After merge but before the release pull request is
merged: merge a `revert:` pull request; the release pull request recalculates. After
release: consumers simply stay on `vN-1`; tags never change. Ship the fix as `vN.0.1`.

## Troubleshooting

| Symptom | Cause | Fix |
| --- | --- | --- |
| Release pull request shows a minor bump | The `!` or footer was lost | The squash commit lacks them: check the repository merges with "pull request title and description". Add `Release-As: N.0.0` in a follow-up |
| Consumer plan replaces a resource you intended to rename | `moved` block missing or wrong address | Add it; `terraform plan` must say "has moved to" |
| `BREAKING CHANGE` text missing from the changelog | Footer not in the last paragraph of the description | Edit the release pull-request description; it becomes the changelog |
