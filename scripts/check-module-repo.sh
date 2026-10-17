#!/usr/bin/env bash
# check-module-repo.sh - check a Terraform module repository against the standard.
#
# Usage:
#   check-module-repo.sh [PATH] [--repo OWNER/NAME] [--template]
#
# PATH is a local clone (default: current directory). The local checks need no
# network. With --repo, the GitHub repository settings, rulesets and security
# features are checked too (needs gh, signed in with read access). --template
# allows the __OWNER__/__TEAM__/__MODULE__ placeholders (for the template itself).
#
# Exit status is non-zero when any check FAILs. WARN lines do not fail the run.
set -uo pipefail

ROOT="."; REPO=""; TEMPLATE=false
while [ $# -gt 0 ]; do
  case "$1" in
    --repo) REPO="$2"; shift 2 ;;
    --template) TEMPLATE=true; shift ;;
    -h|--help) sed -n '2,/^set -uo/p' "${BASH_SOURCE[0]}" | sed '$d' | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) ROOT="$1"; shift ;;
  esac
done
cd "$ROOT" || { echo "cannot cd to $ROOT"; exit 2; }

PASS=0; FAIL=0; WARNS=0
pass() { PASS=$((PASS + 1)); printf 'PASS  %s\n' "$*"; }
fail() { FAIL=$((FAIL + 1)); printf 'FAIL  %s\n' "$*"; }
warn() { WARNS=$((WARNS + 1)); printf 'WARN  %s\n' "$*"; }
check_file() { if [ -f "$1" ]; then pass "$1 exists"; else fail "$1 is missing"; fi; }

echo "== Files (in $(pwd))"
for f in README.md LICENSE CONTRIBUTING.md CHANGELOG.md SECURITY.md main.tf variables.tf outputs.tf versions.tf \
         .gitignore .tflint.hcl .terraform-docs.yml .markdownlint-cli2.jsonc release-please-config.json .release-please-manifest.json \
         .github/CODEOWNERS .github/PULL_REQUEST_TEMPLATE.md .github/dependabot.yml \
         .github/workflows/ci.yml .github/workflows/release-please.yml; do
  check_file "$f"
done
if ls examples/*/main.tf > /dev/null 2>&1; then pass "at least one example under examples/"; else fail "no examples/<name>/main.tf"; fi
if ls tests/*.tftest.hcl > /dev/null 2>&1; then pass "at least one test under tests/"; else fail "no tests/*.tftest.hcl"; fi
if [ -f examples/basic/main.tf ] && [ -f examples/complete/main.tf ]; then pass "examples/basic and examples/complete exist"; else fail "examples/basic/main.tf and examples/complete/main.tf are both required"; fi
for q in tutorials how-to reference explanation; do
  if ls "docs/$q"/*.md > /dev/null 2>&1; then pass "docs/$q has a page"; else fail "docs/$q has no page (Diataxis: tutorial, how-to, reference, explanation)"; fi
done
if [ -f providers.tf ]; then fail "providers.tf present: a module must not configure providers"; fi

echo "== Terraform module rules"
if [ -f versions.tf ]; then
  grep -q 'required_version' versions.tf && pass "versions.tf declares required_version" || fail "versions.tf lacks required_version"
  grep -q 'required_providers' versions.tf && pass "versions.tf declares required_providers" || fail "versions.tf lacks required_providers"
  if grep -E 'version\s*=\s*"' versions.tf | grep -vE '">=\s*[0-9]' > /dev/null; then
    fail "versions.tf has a constraint that is not a plain minimum (>=): $(grep -E 'version\s*=\s*"' versions.tf | grep -vE '">=' | tr -s ' ' | tr '\n' ';')"
  else
    pass "versions.tf uses minimum (>=) constraints only"
  fi
  if grep -Eq 'v[0-9]+\.[0-9]+\.[0-9]+' versions.tf; then
    fail "versions.tf contains a vX.Y.Z string; release-please rewrites every one of them"
  else
    pass "versions.tf contains no vX.Y.Z strings"
  fi
fi
ROOT_TF="$(ls ./*.tf 2> /dev/null || true)"
if [ -n "$ROOT_TF" ]; then
  # Comment lines are dropped so documentation inside the code cannot trip the checks.
  # shellcheck disable=SC2086
  CODE="$(grep -vhE '^\s*(#|//)' $ROOT_TF)"
  echo "$CODE" | grep -qE '^\s*provider\s+"' && fail "a provider block in the module root" || pass "no provider block in the module root"
  echo "$CODE" | grep -qE '^\s*backend\s+"' && fail "a backend block in the module" || pass "no backend block"
  echo "$CODE" | grep -qE 'path\.module\}?/\.\.|path\.(root|cwd)' && fail "reads outside the module directory: $(echo "$CODE" | grep -nE 'path\.module\}?/\.\.|path\.(root|cwd)' | head -3 | tr '\n' ' ')" || pass "reads nothing outside the module directory"
fi

echo "== README and release-please"
if [ -f README.md ]; then
  grep -E '\?ref=v[0-9]+\.[0-9]+\.[0-9]+.*x-release-please-version' README.md > /dev/null && pass "README usage pins ?ref=vX.Y.Z and is annotated x-release-please-version" || fail "README has no '?ref=vX.Y.Z ... # x-release-please-version' usage line"
  grep -q 'BEGIN_TF_DOCS' README.md && grep -q 'END_TF_DOCS' README.md && pass "README has terraform-docs markers" || fail "README lacks BEGIN_TF_DOCS/END_TF_DOCS markers"
  grep -q '^## Documentation' README.md && pass "README has a Documentation section" || fail "README lacks the '## Documentation' section linking docs/"
  grep -Eq 'version\s*=\s*"~>' README.md && fail "README contains 'version = \"~>': release-please's terraform-module strategy rewrites the first one" || pass "README has no 'version = \"~>' text"
fi
if [ -f release-please-config.json ]; then
  if jq empty release-please-config.json 2> /dev/null; then
    [ "$(jq -r '.packages["."]["release-type"] // empty' release-please-config.json)" = "terraform-module" ] && pass "release-type is terraform-module" || fail "release-please-config.json: packages['.'].release-type must be terraform-module"
    jq -e '.packages["."]["extra-files"] // [] | index("README.md")' release-please-config.json > /dev/null && pass "README.md is in extra-files" || fail "release-please-config.json: README.md missing from packages['.'].extra-files"
    [ "$(jq -r 'if has("include-component-in-tag") then .["include-component-in-tag"] | tostring else "unset" end' release-please-config.json)" = "false" ] && pass "include-component-in-tag is false (tags are vX.Y.Z)" || warn "set include-component-in-tag: false so tags are plain vX.Y.Z"
  else
    fail "release-please-config.json is not valid JSON"
  fi
fi
if [ -f .release-please-manifest.json ]; then
  jq -e 'type == "object"' .release-please-manifest.json > /dev/null 2>&1 && pass ".release-please-manifest.json is a JSON object" || fail ".release-please-manifest.json is not a JSON object"
fi
[ -f CHANGELOG.md ] && { head -1 CHANGELOG.md | grep -q '^# Changelog' && pass "CHANGELOG.md starts with '# Changelog'" || fail "CHANGELOG.md must start with '# Changelog' (release-please inserts entries under it)"; }

echo "== Workflows and ownership"
[ -f .github/workflows/ci.yml ] && { grep -q 'terraform-module-standards/.github/workflows/terraform-ci.yml@' .github/workflows/ci.yml && pass "ci.yml calls the shared terraform-ci workflow" || fail "ci.yml does not call terraform-module-standards/.github/workflows/terraform-ci.yml"; }
[ -f .github/workflows/release-please.yml ] && { grep -q 'terraform-module-standards/.github/workflows/terraform-release.yml@' .github/workflows/release-please.yml && pass "release-please.yml calls the shared terraform-release workflow" || fail "release-please.yml does not call terraform-module-standards/.github/workflows/terraform-release.yml"; }
[ -f .github/workflows/release-please.yml ] && { grep -q 'workflow_dispatch' .github/workflows/release-please.yml && pass "release-please.yml can be rerun with workflow_dispatch" || warn "release-please.yml has no workflow_dispatch trigger (needed to rerun a failed release or the dev sync)"; }
[ -f .github/workflows/ci.yml ] && { grep -Eq 'branches: *\[ *dev' .github/workflows/ci.yml && pass "ci.yml runs on pushes to dev" || warn "ci.yml does not run on pushes to dev (push: branches: [dev, main])"; }
[ -f .github/dependabot.yml ] && { grep -q 'target-branch: dev' .github/dependabot.yml && pass "Dependabot version updates target dev" || warn "dependabot.yml has no 'target-branch: dev'; version updates would target the default branch"; }
if [ -f .github/CODEOWNERS ]; then
  grep -Eq '^\*\s+@' .github/CODEOWNERS && pass "CODEOWNERS has a default owner" || warn "CODEOWNERS has no '* @owner' rule yet; add the owning team once it exists"
fi
LEFT="$(grep -rlI --exclude-dir=.git --exclude-dir=.terraform -e '__OWNER__' -e '__TEAM__' -e '__MODULE__' -e '__DESCRIPTION__' -e 'REPLACE_ME' . 2> /dev/null || true)"
if $TEMPLATE; then
  [ -n "$LEFT" ] && pass "template placeholders present (expected with --template)" || warn "no placeholders found; is this really the template?"
else
  [ -z "$LEFT" ] && pass "no template placeholders left" || fail "template placeholders remain in: $(echo "$LEFT" | tr '\n' ' ')"
  STUBS="$(grep -rlI --exclude-dir=.git --exclude-dir=.terraform -e '<!-- TEMPLATE:' . 2> /dev/null || true)"
  [ -z "$STUBS" ] && pass "no template stub pages left" || fail "template stub text remains in: $(echo "$STUBS" | tr '\n' ' ')"
fi

echo "== Hygiene"
if [ -f .gitignore ]; then
  for pat in '.terraform.lock.hcl' '*.tfstate' '*.tfvars'; do
    grep -qF "$pat" .gitignore && pass ".gitignore covers $pat" || fail ".gitignore does not cover $pat"
  done
fi
if git rev-parse --is-inside-work-tree > /dev/null 2>&1; then
  TRACKED="$(git ls-files | grep -E '(^|/)(\.terraform\.lock\.hcl|.*\.tfstate.*|.*\.tfvars|.*\.tfplan)$' | grep -v '\.example$' || true)"
  [ -z "$TRACKED" ] && pass "no lock, state, plan or tfvars file is tracked" || fail "tracked files that must not be: $(echo "$TRACKED" | tr '\n' ' ')"
fi
if command -v terraform > /dev/null 2>&1; then
  terraform fmt -check -recursive > /dev/null 2>&1 && pass "terraform fmt -check passes" || fail "terraform fmt -check reports unformatted files"
fi

if [ -n "$REPO" ]; then
  echo "== GitHub: ${REPO}"
  if ! command -v gh > /dev/null 2>&1; then fail "gh is required for --repo"; else
    INFO="$(gh api "repos/${REPO}" 2> /dev/null || true)"
    if [ -z "$INFO" ]; then fail "cannot read repos/${REPO}"; else
      j() { printf '%s' "$INFO" | jq -r "$1"; }
      [ "$(j .allow_squash_merge)" = "true" ] && [ "$(j .allow_merge_commit)" = "false" ] && [ "$(j .allow_rebase_merge)" = "false" ] && pass "squash is the only merge method" || fail "merge methods: squash=$(j .allow_squash_merge) merge=$(j .allow_merge_commit) rebase=$(j .allow_rebase_merge); only squash may be enabled"
      [ "$(j .squash_merge_commit_title)" = "PR_TITLE" ] && [ "$(j .squash_merge_commit_message)" = "PR_BODY" ] && pass "squash commit = PR title + PR body" || fail "squash commit defaults are $(j .squash_merge_commit_title)/$(j .squash_merge_commit_message); need PR_TITLE/PR_BODY"
      [ "$(j .delete_branch_on_merge)" = "true" ] && pass "branches are deleted on merge" || fail "delete_branch_on_merge is off"
      [ "$(j .is_template)" = "false" ] && pass "not a template repository" || warn "repository is marked as a template"
      printf '%s' "$INFO" | jq -e '.topics | index("terraform-module")' > /dev/null && pass "topic terraform-module set" || warn "topic terraform-module missing"
      echo "info  visibility: $(j .visibility); default branch: $(j .default_branch)"
      SS="$(j '.security_and_analysis.secret_scanning.status // "unavailable"')"
      [ "$SS" = "enabled" ] && pass "secret scanning enabled" || warn "secret scanning: ${SS}"
      if gh api "repos/${REPO}/vulnerability-alerts" > /dev/null 2>&1; then pass "Dependabot alerts enabled"; else fail "Dependabot alerts disabled"; fi
      PVR="$(gh api "repos/${REPO}/private-vulnerability-reporting" --jq .enabled 2> /dev/null || echo unknown)"
      [ "$PVR" = "true" ] && pass "private vulnerability reporting enabled (SECURITY.md relies on it)" || warn "private vulnerability reporting: ${PVR}"
      if gh api "repos/${REPO}/branches/dev" > /dev/null 2>&1; then pass "integration branch dev exists"; else fail "no dev branch (feature work merges into dev; dev is promoted to main)"; fi
      RS="$(gh api "repos/${REPO}/rulesets" 2> /dev/null || echo '[]')"
      BR_ID=""; DEV_RS=""
      for id in $(printf '%s' "$RS" | jq -r '.[] | select(.target == "branch") | .id'); do
        INCL="$(gh api "repos/${REPO}/rulesets/${id}" --jq '.conditions.ref_name.include[]' 2> /dev/null || true)"
        printf '%s\n' "$INCL" | grep -qx 'refs/heads/main' && BR_ID="$id"
        printf '%s\n' "$INCL" | grep -qx 'refs/heads/dev' && DEV_RS="$id"
      done
      [ -z "$BR_ID" ] && BR_ID="$(printf '%s' "$RS" | jq -r '[.[] | select(.target == "branch")][0].id // empty')"
      [ -n "$DEV_RS" ] && pass "a ruleset targets refs/heads/dev" || warn "no ruleset targets refs/heads/dev"
      if [ -n "$BR_ID" ]; then
        BR="$(gh api "repos/${REPO}/rulesets/${BR_ID}")"
        printf '%s' "$BR" | jq -e '.conditions.ref_name.include | index("refs/heads/main")' > /dev/null && pass "main ruleset targets refs/heads/main by name" || warn "main ruleset targets '$(printf '%s' "$BR" | jq -r '.conditions.ref_name.include | join(",")')' rather than refs/heads/main"
        printf '%s' "$BR" | jq -e '.enforcement == "active"' > /dev/null && pass "branch ruleset '$(printf '%s' "$BR" | jq -r .name)' is active" || fail "branch ruleset is not active"
        printf '%s' "$BR" | jq -e '[.rules[] | select(.type == "pull_request")] | length > 0' > /dev/null && pass "ruleset requires a pull request" || fail "ruleset has no pull_request rule"
        printf '%s' "$BR" | jq -e '[.rules[] | select(.type == "required_status_checks") | .parameters.required_status_checks[] | select(.context == "ci / CI passed")] | length > 0' > /dev/null && pass "ruleset requires 'ci / CI passed'" || fail "ruleset does not require the status check 'ci / CI passed'"
        printf '%s' "$BR" | jq -e '[.rules[] | select(.type == "deletion")] | length > 0 and ([.rules[] | select(.type == "non_fast_forward")] | length > 0)' > /dev/null && pass "ruleset blocks deletion and force-push" || fail "ruleset must block deletion and non_fast_forward"
        printf '%s' "$BR" | jq -e '[.rules[] | select(.type == "pull_request") | .parameters.require_code_owner_review] | index(true)' > /dev/null && pass "ruleset requires code owner review" || warn "ruleset does not require code owner review"
      else
        fail "no branch ruleset on ${REPO}"
      fi
      TG_ID="$(printf '%s' "$RS" | jq -r '[.[] | select(.target == "tag")][0].id // empty')"
      if [ -n "$TG_ID" ]; then
        TG="$(gh api "repos/${REPO}/rulesets/${TG_ID}")"
        printf '%s' "$TG" | jq -e '.conditions.ref_name.include | index("refs/tags/v*")' > /dev/null && pass "tag ruleset covers refs/tags/v*" || fail "tag ruleset does not include refs/tags/v*"
        printf '%s' "$TG" | jq -e '[.rules[].type] | index("deletion") and index("update")' > /dev/null && pass "tag ruleset blocks deletion and update" || fail "tag ruleset must block deletion and update"
        printf '%s' "$TG" | jq -e '[.rules[].type] | index("creation")' > /dev/null && pass "tag ruleset restricts creation to the release App" || warn "tag ruleset leaves creation open: anyone with write access can cut a release tag"
      else
        fail "no tag ruleset on ${REPO}"
      fi
      EFFECTIVE="$(gh api "repos/${REPO}/rules/branches/$(j .default_branch)" --jq 'length' 2> /dev/null || echo 0)"
      [ "${EFFECTIVE}" -gt 0 ] && pass "GitHub reports ${EFFECTIVE} rule(s) in effect on $(j .default_branch)" || warn "GitHub reports no rules in effect on $(j .default_branch); on GitHub Free, private repositories cannot have rulesets"
      CO_ERR="$(gh api "repos/${REPO}/codeowners/errors" --jq '.errors | length' 2> /dev/null || echo "?")"
      [ "$CO_ERR" = "0" ] && pass "CODEOWNERS has no errors" || warn "CODEOWNERS errors: ${CO_ERR} (gh api repos/${REPO}/codeowners/errors)"
      SECRETS="$(gh secret list --repo "$REPO" 2> /dev/null | awk '{print $1}' || true)"
      for s in RELEASE_APP_CLIENT_ID RELEASE_APP_PRIVATE_KEY; do
        echo "$SECRETS" | grep -qx "$s" && pass "secret ${s} visible to the repository" || warn "secret ${s} not visible to the repository (set it, or provide it as an organisation secret)"
      done
    fi
  fi
fi

echo
echo "${PASS} passed, ${FAIL} failed, ${WARNS} warnings"
[ "$FAIL" -eq 0 ]
