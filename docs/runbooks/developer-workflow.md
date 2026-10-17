# Developer workflow

## Purpose

Change a module and get it onto `dev`, where it waits for the next promotion to `main`
([promote-to-main.md](promote-to-main.md)). The daily cheat sheet.

## Prerequisites

Terraform 1.9+, `tflint`, `terraform-docs`, `gh`. Optional: `pre-commit install` once
per clone to run the same checks on every commit.

## Steps

```bash
git switch dev && git pull --ff-only
git switch -c feat/custom-kms-key          # feat/ fix/ docs/ chore/ refactor/ test/ ci/

# ... edit main.tf, variables.tf, outputs.tf, tests/, examples/ ...

terraform fmt -recursive
terraform init -backend=false && terraform validate
terraform test
tflint --init && tflint --recursive
terraform-docs .                            # refresh the README tables

git add main.tf variables.tf README.md tests/inputs.tftest.hcl   # name the files; never git add -A
git status --short
git commit -m "feat: add support for a customer managed KMS key"
git push -u origin feat/custom-kms-key
gh pr create --base dev --fill               # title = Conventional Commit; body in prose
```

Then:

1. CI runs. Fix anything red and push again.
2. A code owner reviews. Resolve every conversation.
3. Squash merge. The pull-request title becomes the commit on `dev`.
4. The branch is deleted automatically.
5. Your change waits on `dev`. A maintainer promotes `dev` to `main`
   ([promote-to-main.md](promote-to-main.md)); release-please then opens the release
   pull request. Nothing else to do.

Title rules that matter: `feat:` for new capability, `fix:` for a bug, `feat!:` or
`fix!:` for a breaking change (then also add a `BREAKING CHANGE: ...` footer as the
last paragraph of the description). `docs:`, `chore:`, `refactor:`, `test:` and `ci:`
never release on their own.

## Validation

- The pull request shows `ci / CI passed` green.
- After merge, `git fetch origin && git log --oneline origin/main..origin/dev` lists
  your change among those waiting for promotion.

## Rollback

Before merge: push more commits or close the pull request. After merge into `dev`:
open a pull request into `dev` titled `revert: <original title>` from `git revert <sha>`
before the next promotion, and nothing ever ships. After promotion and release: the
same revert, promoted, releases as a patch.

## Troubleshooting

| Symptom | Fix |
| --- | --- |
| `PR title` check fails | Retitle the pull request; the type must be one of `feat fix docs chore refactor test ci revert` |
| `Docs` check fails | Run `terraform-docs .` and commit `README.md` |
| `Test (Terraform <minimum>)` fails but `latest` passes | You used a feature newer than the module's `required_version`. Avoid it, or raise the minimum in a `feat!:` pull request |
| More in [troubleshooting.md](troubleshooting.md) | |
