#!/usr/bin/env bash
# new-module-repo.sh - create and configure one Terraform module repository.
#
# Creates OWNER/terraform-aws-NAME from the template repository, replaces the
# template placeholders, applies the repository settings and rulesets of the
# standard, and prints what to do next. Every step is idempotent: re-run it
# with --configure-only to bring an existing repository up to the standard.
#
# Usage:
#   new-module-repo.sh --owner OWNER --name NAME --team TEAM [options]
#
# Options:
#   --owner OWNER            GitHub organisation (or user) that hosts the repository
#   --name NAME              Capability name, e.g. ecr-repository -> terraform-aws-ecr-repository
#   --team TEAM              Team slug that owns the module (CODEOWNERS, maintain access)
#   --description TEXT       Repository description (default: "Terraform module for NAME on AWS")
#   --visibility public|private   Default: private
#   --template OWNER/REPO    Template repository (default: OWNER/terraform-aws-module-template)
#   --dest DIR               Where to clone (default: ./terraform-aws-NAME)
#   --release-app-client-id ID     Set the RELEASE_APP_CLIENT_ID repository secret
#   --release-app-key-file PATH    Set the RELEASE_APP_PRIVATE_KEY repository secret from a file
#   --configure-only         Skip creation; apply settings and rulesets to an existing repository
#   --dry-run                Print every command instead of running it
#   -h, --help               Show this help
#
# Requires: gh (signed in; "repo" scope, plus "admin:org" for team access), jq, git, perl.
set -euo pipefail

OWNER=""; NAME=""; TEAM=""; DESCRIPTION=""; VISIBILITY="private"; TEMPLATE=""; DEST=""
APP_CLIENT_ID=""; APP_KEY_FILE=""; CONFIGURE_ONLY=false; DRY_RUN=false
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RULESETS_DIR="${HERE}/../rulesets"

usage() { sed -n '2,/^set -euo/p' "${BASH_SOURCE[0]}" | sed '$d' | sed 's/^# \{0,1\}//'; }
log()  { printf '\n==> %s\n' "$*"; }
warn() { printf 'WARN: %s\n' "$*" >&2; }
die()  { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
run()  { if $DRY_RUN; then { printf '+'; printf ' %q' "$@"; printf '\n'; } >&2; else "$@"; fi; }

while [ $# -gt 0 ]; do
  case "$1" in
    --owner) OWNER="$2"; shift 2 ;;
    --name) NAME="$2"; shift 2 ;;
    --team) TEAM="$2"; shift 2 ;;
    --description) DESCRIPTION="$2"; shift 2 ;;
    --visibility) VISIBILITY="$2"; shift 2 ;;
    --template) TEMPLATE="$2"; shift 2 ;;
    --dest) DEST="$2"; shift 2 ;;
    --release-app-client-id) APP_CLIENT_ID="$2"; shift 2 ;;
    --release-app-key-file) APP_KEY_FILE="$2"; shift 2 ;;
    --configure-only) CONFIGURE_ONLY=true; shift ;;
    --dry-run) DRY_RUN=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown argument: $1 (try --help)" ;;
  esac
done

[ -n "$OWNER" ] || die "--owner is required"
[ -n "$NAME" ] || die "--name is required"
case "$VISIBILITY" in public|private) ;; *) die "--visibility must be public or private" ;; esac
NAME="${NAME#terraform-aws-}"
REPO="terraform-aws-${NAME}"
FULL="${OWNER}/${REPO}"
TEMPLATE="${TEMPLATE:-${OWNER}/terraform-aws-module-template}"
DEST="${DEST:-./${REPO}}"
DESCRIPTION="${DESCRIPTION:-Terraform module for ${NAME} on AWS}"

for tool in gh jq git perl; do command -v "$tool" > /dev/null || die "$tool is required"; done
[ -f "${RULESETS_DIR}/main.json" ] || die "rulesets not found at ${RULESETS_DIR}; run from a clone of terraform-module-standards"

log "Preflight"
gh auth status > /dev/null || die "gh is not signed in"
OWNER_TYPE="$(gh api "users/${OWNER}" --jq .type 2> /dev/null || echo unknown)"
echo "owner ${OWNER} is a ${OWNER_TYPE}; repository ${FULL}; visibility ${VISIBILITY}"
if [ "$OWNER_TYPE" = "Organization" ]; then
  PLAN="$(gh api "orgs/${OWNER}" --jq '.plan.name // "unknown"' 2> /dev/null || echo unknown)"
  echo "organisation plan: ${PLAN}"
  if [ "$PLAN" = "free" ] && [ "$VISIBILITY" = "private" ]; then
    warn "GitHub Free enforces rulesets and CODEOWNERS on PUBLIC repositories only."
    warn "GitHub refuses rulesets on a private repository on this plan, so the ruleset step will fail. See docs/standard.md, section 12."
  fi
  if [ -z "$TEAM" ]; then
    warn "--team not given; CODEOWNERS will keep the __TEAM__ placeholder and GitHub will ignore it"
  fi
fi

if ! $CONFIGURE_ONLY; then
  log "Create ${FULL} from ${TEMPLATE}"
  if gh repo view "$FULL" > /dev/null 2>&1; then
    die "${FULL} already exists; use --configure-only to apply the standard to it"
  fi
  run gh repo create "$FULL" --template "$TEMPLATE" "--${VISIBILITY}" \
    --description "$DESCRIPTION" --disable-wiki
fi

if [ ! -d "$DEST/.git" ]; then
  log "Clone to ${DEST}"
  run gh repo clone "$FULL" "$DEST"
fi

if [ "$OWNER_TYPE" = "Organization" ] && [ -n "$TEAM" ]; then
  log "Give team ${TEAM} maintain access (needed for CODEOWNERS to resolve)"
  run gh api -X PUT "orgs/${OWNER}/teams/${TEAM}/repos/${FULL}" -f permission=maintain \
    || warn "could not grant team access; does the team exist? (gh api orgs/${OWNER}/teams)"
fi

log "Replace template placeholders"
if $DRY_RUN; then
  echo "+ perl -pi -e 's/__OWNER__/${OWNER}/g; s/__TEAM__/${TEAM:-__TEAM__}/g; s/__MODULE__/${NAME}/g; s/__DESCRIPTION__/${DESCRIPTION}/g' <files containing placeholders>"
else
  # A read loop rather than mapfile, which needs bash 4; macOS ships bash 3.2.
  FILES=()
  while IFS= read -r f; do FILES+=("$f"); done \
    < <(cd "$DEST" || exit; grep -rlI --exclude-dir=.git -e '__OWNER__' -e '__TEAM__' -e '__MODULE__' -e '__DESCRIPTION__' . || true)
  # CODEOWNERS is rewritten even when the template already names a team, so --team wins.
  [ -n "$TEAM" ] && [ -f "$DEST/.github/CODEOWNERS" ] && FILES+=("./.github/CODEOWNERS")
  if [ "${#FILES[@]}" -gt 0 ]; then
    (
      cd "$DEST"
      TEAM_VALUE="${TEAM:-__TEAM__}"
      export OWNER NAME DESCRIPTION TEAM_VALUE
      perl -pi -e 's/__OWNER__/$ENV{OWNER}/g; s/__TEAM__/$ENV{TEAM_VALUE}/g; s/__MODULE__/$ENV{NAME}/g; s/__DESCRIPTION__/$ENV{DESCRIPTION}/g' "${FILES[@]}"
      [ -n "$TEAM" ] && perl -pi -e 's{^\*\s+\@\S+}{* \@$ENV{OWNER}/$ENV{TEAM_VALUE}}' .github/CODEOWNERS
      git add -- "${FILES[@]}"
      git status --short
      if ! git diff --cached --quiet; then
        git commit -q -m "chore: configure repository for ${FULL}"
        git push -q origin HEAD
        echo "pushed placeholder substitution to $(git branch --show-current)"
      else
        echo "nothing to substitute"
      fi
    )
  else
    echo "no placeholders left"
  fi
fi

log "Repository settings: squash merges only, PR title + body as the commit, branch clean-up"
SETTINGS="$(jq -n '{
  allow_squash_merge: true,
  allow_merge_commit: false,
  allow_rebase_merge: false,
  allow_auto_merge: true,
  delete_branch_on_merge: true,
  allow_update_branch: true,
  squash_merge_commit_title: "PR_TITLE",
  squash_merge_commit_message: "PR_BODY",
  has_wiki: false,
  has_projects: false
}')"
if $DRY_RUN; then echo "+ gh api -X PATCH repos/${FULL} --input <settings json>"; else
  printf '%s' "$SETTINGS" | gh api -X PATCH "repos/${FULL}" --input - > /dev/null
fi

log "Dependency alerts and security updates"
run gh api -X PUT "repos/${FULL}/vulnerability-alerts" || warn "could not enable Dependabot alerts"
run gh api -X PUT "repos/${FULL}/automated-security-fixes" || warn "could not enable Dependabot security updates"
# SECURITY.md tells reporters to use private vulnerability reporting.
run gh api -X PUT "repos/${FULL}/private-vulnerability-reporting" || warn "could not enable private vulnerability reporting"
if $DRY_RUN; then echo "+ gh api -X PATCH repos/${FULL} --input <secret scanning json>"; else
  if ! jq -n '{security_and_analysis:{secret_scanning:{status:"enabled"},secret_scanning_push_protection:{status:"enabled"}}}' \
      | gh api -X PATCH "repos/${FULL}" --input - > /dev/null 2>&1; then
    warn "secret scanning could not be enabled (free on public repositories; needs GitHub Secret Protection on private ones)"
  fi
fi

log "Topics"
run gh repo edit "$FULL" --add-topic terraform --add-topic terraform-module --add-topic aws

log "Rulesets"
apply_ruleset() {
  local file="$1" name id=""
  name="$(jq -r .name "$file")"
  if ! $DRY_RUN; then
    id="$(gh api "repos/${FULL}/rulesets" --jq ".[] | select(.name == \"${name}\") | .id" 2> /dev/null || true)"
    [[ "$id" =~ ^[0-9]+$ ]] || id=""
  fi
  local verb; verb="$($DRY_RUN && echo would || echo did)"
  if [ -n "$id" ]; then
    run gh api -X PUT "repos/${FULL}/rulesets/${id}" --input "$file" > /dev/null \
      && echo "${verb} update ruleset '${name}' (${id})"
  else
    run gh api -X POST "repos/${FULL}/rulesets" --input "$file" > /dev/null \
      && echo "${verb} create ruleset '${name}'"
  fi
}
for f in "${RULESETS_DIR}/main.json" "${RULESETS_DIR}/release-tags.json"; do
  apply_ruleset "$f" || warn "ruleset $(basename "$f") was not applied; check the plan and your permissions"
done

if [ -n "$APP_CLIENT_ID" ] || [ -n "$APP_KEY_FILE" ]; then
  log "Release GitHub App secrets"
  [ -n "$APP_CLIENT_ID" ] && run gh secret set RELEASE_APP_CLIENT_ID --repo "$FULL" --body "$APP_CLIENT_ID"
  if [ -n "$APP_KEY_FILE" ]; then
    [ -f "$APP_KEY_FILE" ] || die "key file not found: $APP_KEY_FILE"
    if $DRY_RUN; then echo "+ gh secret set RELEASE_APP_PRIVATE_KEY --repo ${FULL} < ${APP_KEY_FILE}"; else
      gh secret set RELEASE_APP_PRIVATE_KEY --repo "$FULL" < "$APP_KEY_FILE"
    fi
  fi
else
  echo "release App secrets not set here; they must exist as organisation secrets or be set with gh secret set"
fi

log "Done. Next steps"
cat <<NEXT
  1. cd ${DEST}
  2. Replace the placeholder module with your Terraform code (main.tf, variables.tf,
     outputs.tf, examples/basic, tests/), then run the local checks:
       terraform fmt -recursive && terraform init -backend=false && terraform validate
       terraform test && tflint --init && tflint --recursive && terraform-docs .
  3. Open a pull request titled "feat: add the ${NAME} module". End its description
     with the line  Release-As: 1.0.0  so the first release is v1.0.0.
  4. Merge it; release-please opens "chore(main): release 1.0.0"; merge that too.
  5. Check compliance: ${HERE}/check-module-repo.sh ${DEST} --repo ${FULL}
NEXT
