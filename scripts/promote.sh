#!/usr/bin/env bash
# Open the promotion pull request dev -> main for the repository in the current
# directory.
#
#   scripts/promote.sh [--dry-run]
#
# What it does:
#   1. Checks that dev contains main (main is merged back into dev by a pull
#      request after each release; if that has not happened, stop).
#   2. Checks that no promotion pull request is already open.
#   3. Builds the pull-request description from the squash commits on dev that
#      main does not have: one BEGIN_NESTED_COMMIT ... END_NESTED_COMMIT block
#      per change, holding its Conventional Commit header and its BREAKING
#      CHANGE / Release-As footers. That description becomes the body of the
#      squash commit on main (repository setting: squash commit = PR title + PR
#      body), and release-please parses every block as a separate change. Bare
#      headers are not enough: release-please splits on "type: " and
#      "type(scope): " only, so a "feat!: " change would be lost.
#   4. Opens the pull request with the title "chore(promote): dev to main".
#
# Requires: git, gh (authenticated), a clone with an "origin" remote.
set -euo pipefail

DRY_RUN=false
case "${1:-}" in
  --dry-run) DRY_RUN=true ;;
  -h|--help) sed -n '2,/^set -euo/p' "${BASH_SOURCE[0]}" | sed '$d' | sed 's/^# \{0,1\}//'; exit 0 ;;
  "") ;;
  *) echo "unknown argument: $1" >&2; exit 2 ;;
esac

die() { echo "promote: $*" >&2; exit 1; }

REPO="$(gh repo view --json nameWithOwner --jq .nameWithOwner)" || die "run inside a clone with a GitHub remote"
git fetch -q origin main dev || die "could not fetch origin/main and origin/dev; does dev exist?"

if ! git merge-base --is-ancestor origin/main origin/dev; then
  die "dev does not contain main. Open a pull request from main into dev; an admin merges it with a merge commit (allow merge commits for that merge only): gh pr create --repo ${REPO} --base dev --head main --title 'chore(sync): merge main into dev'"
fi

EXISTING="$(gh pr list --repo "$REPO" --base main --head dev --state open --json number --jq '.[0].number // empty')"
[ -n "$EXISTING" ] && die "promotion pull request #${EXISTING} is already open: gh pr view ${EXISTING} --repo ${REPO}"

COUNT="$(git rev-list --count --no-merges origin/main..origin/dev)"
[ "$COUNT" -gt 0 ] || die "dev has no commits that main lacks; nothing to promote"

# One block per squash commit, oldest first: the subject, then only the footers
# release-please acts on. Everything else in a commit body (the pull-request
# prose) is left out, so that a prose line can never be mistaken for a header
# and a header can never be swallowed by prose.
BODY="$(
  printf 'Promotes %s change(s) from dev to main. Squash merge only. Each block below is one change release-please reads from the squash commit.\n' "$COUNT"
  for sha in $(git rev-list --reverse --no-merges origin/main..origin/dev); do
    printf '\nBEGIN_NESTED_COMMIT\n%s\n' "$(git log -1 --format=%s "$sha")"
    # A footer runs on to the next blank line or footer token, so keep its
    # continuation lines: a wrapped BREAKING CHANGE note would be cut short.
    FOOTERS="$(git log -1 --format=%b "$sha" | awk '
      tolower($0) ~ /^(breaking[- ]change|release-as): / { keep = 1; print; next }
      /^$/ || /^[A-Za-z-]+(: | #)/                        { keep = 0 }
      keep                                                { print }
    ')"
    [ -n "$FOOTERS" ] && printf '\n%s\n' "$FOOTERS"
    printf 'END_NESTED_COMMIT\n'
  done
)"

TITLE="chore(promote): dev to main"

if $DRY_RUN; then
  printf 'Would open on %s: %s\n\n%s\n' "$REPO" "$TITLE" "$BODY"
  exit 0
fi

gh pr create --repo "$REPO" --base main --head dev --title "$TITLE" --body "$BODY"
echo
echo "Review the description: it is the squash commit release-please will read. Squash merge only; never a merge commit."
