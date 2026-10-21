# Release a module version

## Purpose

Turn merged pull requests into a tagged, documented release. release-please does the
mechanical work; a person reviews and merges one pull request.

## Prerequisites

- The repository was created with [create-repository.md](create-repository.md), so
  `release-please.yml` runs on every push to `main` and GitHub Actions may create
  pull requests.
- A promotion pull request ([promote-to-main.md](promote-to-main.md)) carrying at
  least one `feat:`, `fix:` or breaking change has merged into `main` since the last
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
changelog every time `main` changes, so leave it open until you want to release. Its
changelog lists the changes from the promotion's description, one entry per line.

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

Wait for the `workflow.yml` checks and one approval, then squash merge. Within a minute
release-please creates the tag `vX.Y.Z` and the GitHub Release.

### 4. Tell consumers

Consumers with Dependabot's `terraform` ecosystem get an upgrade pull request
automatically. Others follow [upgrade-module-version.md](upgrade-module-version.md).

### First release: `v1.0.0`

The `terraform-module` release type starts at `0.1.0`. To start at `1.0.0`, the
**first** pull request into `dev` that lands a `feat:` must end its description with
the line:

```text
Release-As: 1.0.0
```

Keep it at the bottom of the description. `scripts/promote.sh` copies `Release-As:`
footers into the promotion's description, directly under the change they belong to, so
the footer reaches `main`. release-please then opens `chore(main): release 1.0.0`.
Merge it exactly as in step 3.

If the first release pull request already says `0.1.0`, merge a tiny `fix:` pull
request whose description ends with `Release-As: 1.0.0`; release-please recalculates.

## Validation

```bash
gh release view "vX.Y.Z" --repo "${OWNER}/${REPO}"
git ls-remote --tags "https://github.com/${OWNER}/${REPO}.git" "vX.Y.Z"
gh api "repos/${OWNER}/${REPO}/contents/.release-please-manifest.json" --jq '.content' | base64 -d
```

The release exists, the tag points at the squash commit of the release pull request,
and the manifest holds the new version. Then merge the release back into `dev`: open a
pull request from `main` into `dev`; an admin allows merge commits in the repository
settings, merges it with a merge commit, and turns merge commits off again. Afterwards
this prints `dev contains main`:

```bash
git fetch origin && git merge-base --is-ancestor origin/main origin/dev && echo "dev contains main"
```

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
| A change merged into `dev` is missing from the release pull request | The promotion was merged with a merge commit, or its description lost the line | Edit the merged promotion's description: add a `BEGIN_COMMIT_OVERRIDE` … `END_COMMIT_OVERRIDE` block holding the promotion's title line, a blank line, and one `BEGIN_NESTED_COMMIT` … `END_NESTED_COMMIT` block per change (the shape `promote.sh --dry-run` prints); then rerun the latest release-please run (`gh run rerun`) ([promote-to-main.md](promote-to-main.md), Troubleshooting) |
| `promote.sh` says `dev does not contain main` | `main` has not been merged back into `dev` since the last release | Open a pull request from `main` into `dev`; an admin allows merge commits in the repository settings, merges it with a merge commit (a squash would not make `main` part of `dev`'s history), and turns merge commits off again |
| Release pull request shows no status checks | Expected: release-please runs as `GITHUB_TOKEN`, and pull requests it opens start no workflows | Review the changelog and merge; no check is required |
| Version is wrong | A title said `feat` where `fix` was meant, or `!` was missing | Add a footer in a follow-up pull request: `Release-As: X.Y.Z` |
| The release workflow failed on "Resource not accessible by integration" | The release job lacks a write permission | Keep the `permissions` block in `release-please.yml`; check no organisation policy caps it, then re-run |
| "GitHub Actions is not permitted to create or approve pull requests" | The repository or organisation setting is off | Settings → Actions → General → Workflow permissions: allow GitHub Actions to create and approve pull requests, then re-run |
| Tag created, no GitHub Release | Workflow was interrupted between the two steps | Re-run the workflow from the Actions tab; release-please is idempotent |
