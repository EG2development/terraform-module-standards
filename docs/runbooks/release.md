# Release a module version

## Purpose

Turn merged pull requests into a tagged, documented release. release-please does the
mechanical work; a person reviews and merges one pull request.

## Prerequisites

- The repository was created with [create-repository.md](create-repository.md), so
  `release-please.yml` runs on every push to `main` and the release App secrets are
  available.
- At least one `feat:` or `fix:` (or breaking) pull request has merged since the last
  release. `docs:`, `chore:`, `refactor:`, `test:` and `ci:` alone release nothing.

```bash
OWNER=EG2development
REPO=terraform-aws-ecr-repository
```

## Steps

### 1. Find the release pull request

```bash
gh pr list --repo "${OWNER}/${REPO}" --label "autorelease: pending"
```

Its title is `chore(main): release X.Y.Z`. release-please recalculates `X.Y.Z` and the
changelog every time `main` changes, so leave it open until you want to release.

### 2. Review it

The diff touches three files:

| File | Expect |
| --- | --- |
| `CHANGELOG.md` | A new `## [X.Y.Z]` section with Features, Bug Fixes and, if any, ⚠ BREAKING CHANGES |
| `README.md` | The usage line now reads `?ref=vX.Y.Z` |
| `.release-please-manifest.json` | `"." : "X.Y.Z"` |

Check that the bump matches the changes: a breaking entry must bump the major. If the
version is wrong, the cause is a pull-request title; see Troubleshooting.

To add release notes (migration steps for a major version, for example), edit the
pull request **description**. release-please copies it into `CHANGELOG.md` and the
GitHub Release on merge.

### 3. Merge it

Wait for `ci / CI passed` and one approval, then squash merge. Within a minute
release-please creates the tag `vX.Y.Z` and the GitHub Release.

### 4. Tell consumers

Consumers with Dependabot's `terraform` ecosystem get an upgrade pull request
automatically. Others follow [upgrade-module-version.md](upgrade-module-version.md).

### First release: `v1.0.0`

The `terraform-module` release type starts at `0.1.0`. To start at `1.0.0`, the
**first** pull request that lands a `feat:` must end its description with the line:

```text
Release-As: 1.0.0
```

That line must be the last line of the squash commit, so keep it at the bottom of the
description. release-please then opens `chore(main): release 1.0.0`. Merge it exactly
as in step 3.

If the first release pull request already says `0.1.0`, merge a tiny `fix:` pull
request whose description ends with `Release-As: 1.0.0`; release-please recalculates.

## Validation

```bash
gh release view "vX.Y.Z" --repo "${OWNER}/${REPO}"
git ls-remote --tags "https://github.com/${OWNER}/${REPO}.git" "vX.Y.Z"
gh api "repos/${OWNER}/${REPO}/contents/.release-please-manifest.json" --jq '.content' | base64 -d
```

The release exists, the tag points at the merge commit of the release pull request,
and the manifest holds the new version.

## Rollback

A tag cannot be moved or deleted (the tag ruleset blocks both, on purpose). To
withdraw a release:

1. Merge a pull request titled `revert: <what went wrong>` from `git revert`.
2. Merge the resulting release pull request; it ships a patch.
3. Edit the bad GitHub Release and add a first line: "Superseded by vX.Y.Z+1; do not
   use." Consumers who pinned the bad tag still get working code because tags never
   change; they see the note when they upgrade.

## Troubleshooting

| Symptom | Cause | Fix |
| --- | --- | --- |
| No release pull request after merging | No `feat`/`fix`/breaking commit since the last release, or the squash commit title is not a Conventional Commit | `git log --oneline vLAST..main`; a bad title cannot be rewritten on `main`, so merge an empty `fix:` pull request that describes the change |
| Release pull request has no status checks and cannot merge | release-please ran as `GITHUB_TOKEN` | Check the `RELEASE_APP_*` secrets reach the repository; `gh secret list --repo ${OWNER}/${REPO}` |
| Version is wrong | A title said `feat` where `fix` was meant, or `!` was missing | Add a footer in a follow-up pull request: `Release-As: X.Y.Z` |
| The release workflow failed on "Resource not accessible by integration" | The App lacks a permission | Add Contents, Pull requests and Issues read/write to the App and re-run |
| Tag created, no GitHub Release | Workflow was interrupted between the two steps | Re-run the workflow from the Actions tab; release-please is idempotent |
