# Promote dev to main

## Purpose

Move everything that has accumulated on `dev` into `main` in one reviewed step, in the
form release-please needs to compute the next version. One promotion is one squash
commit on `main` whose description lists every change.

## Prerequisites

- A clone of the module repository with `origin` pointing at GitHub; `gh` signed in.
- `dev` contains `main`: after each release, `main` was merged back into `dev` by a
  pull request; the script checks and refuses otherwise.
- You are not the only reviewer: the promotion needs an approval from someone other
  than the person who opened it (or the organisation-owner bypass, recorded in the
  audit log, in a single-maintainer organisation).

```bash
STANDARDS=~/src/terraform-module-standards   # a clone of this repository
cd ~/src/terraform-aws-ecr-repository
```

## Steps

### 1. See what is waiting

```bash
git fetch origin
git log --oneline --no-merges origin/main..origin/dev
```

Every line is a squash commit from a pull request into `dev`. If one has a title that
is not a Conventional Commit, fix it first with a `fix:` or `revert:` pull request into
`dev`; the title cannot be rewritten later.

### 2. Preview the promotion

```bash
"${STANDARDS}/scripts/promote.sh" --dry-run
```

The description has one `BEGIN_NESTED_COMMIT` … `END_NESTED_COMMIT` block per
change: the subject and any `BREAKING CHANGE:` or `Release-As:` footer. Check that a breaking change carries its
`!` or footer, and that a first release carries `Release-As: 1.0.0`.

### 3. Open the pull request

```bash
"${STANDARDS}/scripts/promote.sh"
```

Title: `chore(promote): dev to main`. The script stops if `dev` does not contain `main`
or if a promotion is already open.

### 4. Review

The diff is everything merged into `dev` since the last promotion. The description is
what release-please will read. Do not edit the description except to remove a change
that must not ship (then also revert it on `dev`). Keep every nested block intact.

### 5. Squash merge

Wait for the `workflow.yml` checks and one approval, then **squash** merge. The merge dialog
pre-fills the title and the description; keep both.

### 6. What happens next

Within a minute release-please opens or updates `chore(main): release X.Y.Z`
([release.md](release.md)). After the release, merge `main` back into `dev`: open a
pull request from `main` into `dev`; an admin allows merge commits in the repository
settings, merges it with a merge commit, and turns merge commits off again.

## Validation

```bash
gh pr list --repo "$(gh repo view --json nameWithOwner --jq .nameWithOwner)" --label "autorelease: pending"
git fetch origin && git merge-base --is-ancestor origin/main origin/dev && echo "dev contains main"
```

The release pull request lists every change from step 2 with the right bump, and `dev`
contains `main` again.

## Rollback

Before merge: close the pull request; nothing happened. After merge, before release:
merge a `revert:` pull request into `dev` and promote again; or close the release pull
request's scope by editing its description. After release: fix forward
([release.md](release.md), Rollback).

## Troubleshooting

| Symptom | Cause | Fix |
| --- | --- | --- |
| `promote: dev does not contain main` | `main` has not been merged back into `dev` since the last release | Open a pull request from `main` into `dev`, resolve any conflict, and ask an admin to merge it with a merge commit, allowing merge commits in the repository settings for that merge only |
| `promote: promotion pull request #N is already open` | A previous promotion was not merged | Merge or close it first; the new changes are in it already if it was reopened on the same `dev` |
| The release pull request misses a change, or files a breaking change under the promotion | The promotion was merged with a merge commit, or its description was edited outside the nested blocks, or it came from a `promote.sh` that wrote bare headers | Edit the merged promotion's description: add a `BEGIN_COMMIT_OVERRIDE` … `END_COMMIT_OVERRIDE` block holding the promotion's title line, a blank line, and one `BEGIN_NESTED_COMMIT` … `END_NESTED_COMMIT` block per change (the shape `promote.sh --dry-run` prints); then rerun the latest release-please run (`gh run rerun`) |
| Wrong bump (minor instead of major) | A breaking change had neither `!` nor a `BREAKING CHANGE:` footer on `dev` | Edit the merged promotion's description with the override block above, adding the footer; rerun |
| A `workflow.yml` check fails only on the promotion | `dev` was green per pull request but the combination is not (a weekly `latest` run found a new provider behaviour, for example) | Fix on a short-lived branch into `dev`, promote again |
