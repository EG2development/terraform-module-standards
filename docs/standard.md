# Terraform module repository standard

One Git repository per Terraform module. Trunk-based development, Conventional Commits,
release-please, semantic version tags, shared CI. This page is the standard. The
[runbooks](runbooks/README.md) are the procedures.

Values used in examples:

| Placeholder | Example | Meaning |
| --- | --- | --- |
| `OWNER` | `EG2development` | GitHub organisation that hosts the repositories |
| `TEAM` | `platform-engineering` | Team that owns the modules |
| `NAME` | `ecr-repository` | The capability a module manages |

## 1. Naming

`terraform-aws-<capability>`. The capability is the one thing the module manages,
singular, lower-case, hyphenated.

| Module | Repository |
| --- | --- |
| An ECR repository | `terraform-aws-ecr-repository` |
| A VPC | `terraform-aws-vpc` |
| An SSM-only bastion instance | `terraform-aws-ssm-bastion` |
| An Aurora PostgreSQL cluster | `terraform-aws-aurora-postgresql` |
| An SNS alert topic with subscriptions | `terraform-aws-sns-alert-topic` |

The form is the one the public Terraform Registry requires, so a module can be
published there later without renaming. Other providers follow the same rule with the
provider's local name: `terraform-google-<capability>`, `terraform-azurerm-<capability>`.

Two repositories support the modules:

| Repository | Holds |
| --- | --- |
| `terraform-module-standards` | This standard, the runbooks, the reusable workflows, the rulesets, the scripts |
| `terraform-aws-module-template` | The GitHub template every new module repository is created from |

## 2. Repository layout

```text
terraform-aws-<capability>/
├── .github/
│   ├── CODEOWNERS
│   ├── PULL_REQUEST_TEMPLATE.md
│   ├── dependabot.yml
│   └── workflows/
│       ├── ci.yml                 # calls terraform-ci.yml from terraform-module-standards
│       └── release-please.yml     # calls terraform-release.yml from terraform-module-standards
├── docs/
│   ├── tutorials/                 # one page: first deployment
│   ├── how-to/                    # one to three pages: common tasks
│   ├── reference/                 # one page: resources, names, IAM granted, permissions needed;
│   │                              #   architecture.drawio and its export, architecture.png
│   └── explanation/               # design-decisions.md, ending with "Left out on purpose"
├── examples/
│   ├── basic/                     # main.tf  variables.tf  outputs.tf  versions.tf
│   └── complete/                  # a realistic production-style call
├── tests/
│   └── *.tftest.hcl               # plan/apply tests against mock_provider
├── .gitignore
├── .pre-commit-config.yaml
├── .release-please-manifest.json
├── .terraform-docs.yml
├── .tflint.hcl
├── CHANGELOG.md                   # written by release-please
├── CONTRIBUTING.md
├── LICENSE
├── README.md
├── SECURITY.md
├── main.tf
├── outputs.tf
├── release-please-config.json
├── variables.tf
└── versions.tf
```

| File | Why it is there |
| --- | --- |
| `main.tf`, `variables.tf`, `outputs.tf`, `versions.tf` | The module. Every input has `description` and `type`; every output has `description`. Split `main.tf` by concern only when it helps (for example `flow_logs.tf`) |
| `examples/basic/` | The minimum call, as a complete root configuration with `source = "../.."`. CI validates and plans it |
| `examples/complete/` | A production-style call that uses the important optional inputs and composes the outputs with other resources. Never more complicated than the module |
| `tests/*.tftest.hcl` | `terraform test` with `mock_provider`: no credentials, nothing created. Pins secure defaults, generated names, every validation, and both examples |
| `docs/` | Four short Diátaxis pages (below). The README stays a front page |
| `.github/workflows/ci.yml` | Twenty lines. Calls the shared CI workflow |
| `.github/workflows/release-please.yml` | Fourteen lines. Calls the shared release workflow |
| `release-please-config.json`, `.release-please-manifest.json` | Release type and the last released version. Module-specific state, so they stay local |
| `.terraform-docs.yml`, `.tflint.hcl` | Tool configuration CI and pre-commit both read. Copied from the template; the compliance check flags drift |
| `CHANGELOG.md` | Owned by release-please. Humans edit it only through the release pull request |
| `CONTRIBUTING.md` | Ten lines: branch, commit title, checks, link to the runbooks |
| `SECURITY.md` | How to report a vulnerability privately (GitHub private vulnerability reporting) and which versions get fixes |
| `LICENSE` | Apache-2.0, the Terraform ecosystem's usual licence |

The four `docs/` pages, each in one mode only:

| Page | Answers | Contains |
| --- | --- | --- |
| `tutorials/<first-deployment>.md` | "Show me it working" | Deploy the basic call, look at the result, destroy it |
| `how-to/<task>.md` | "How do I …" | One task per page: enable an optional feature, change a risky setting safely, compose with other resources |
| `reference/<page>.md` | "What exactly …" | Every resource and when it exists; every generated name and tag; exactly what IAM the module grants; what permissions the caller needs; minimum versions and why; the diagram (`architecture.drawio`, exported beside it as `architecture.png` so GitHub shows it) |
| `explanation/design-decisions.md` | "Why …" | The secure defaults and the trade-offs behind them, ending with a "Left out on purpose" table |

Deliberately absent:

- `providers.tf`. A reusable module never configures a provider or a backend; a
  module with its own `provider` block cannot be called with `count`, `for_each` or
  `depends_on`. The caller does both. `required_providers` lives in `versions.tf`.
- `.terraform.lock.hcl`. Terraform ignores a module's lock file; a committed one would
  only pin CI to one provider version (section 9).
- `.github/release-please/`. release-please reads its two files from the repository
  root.

## 3. Branching: feature → dev → main

```text
short-lived branch ──> pull request ──> CI passes ──> review ──> squash merge into dev ──> branch deleted
dev ──> promotion pull request (scripts/promote.sh) ──> CI passes ──> human approval ──> squash merge into main
main ──> release-please release pull request ──> human merges it ──> tag vX.Y.Z + GitHub Release
main ──> merged back into dev by the release workflow, so dev always contains main
```

| Branch | Role | What merges into it | How |
| --- | --- | --- | --- |
| `feat/*`, `fix/*`, `docs/*`, `chore/*`, `refactor/*`, `test/*`, `ci/*` | One change. Lives for hours or days, then is deleted | Nothing | — |
| `dev` | Integration: everything that passed CI and review and is not yet released. Pull requests from people and from AI agents land here and nowhere else | A short-lived branch, by pull request: `ci / CI passed`, one approval, conversations resolved | Squash. The pull-request title is the Conventional Commit |
| `main` | Release: every commit is a promotion, a release commit or a hotfix. Tags and GitHub Releases are cut from it and from nothing else | `dev`, by the promotion pull request `scripts/promote.sh` opens: `ci / CI passed` on an up-to-date branch, one human approval, code owner review | Squash, with the generated description (section 13) |

1. Branch from `dev`.
2. Make one small change. Run the local checks. Push.
3. Open a pull request into `dev` with a Conventional Commit title.
4. CI passes. One reviewer approves. Resolve every conversation. Squash merge; the
   branch is deleted automatically.
5. When `dev` holds what should ship, a maintainer runs `scripts/promote.sh`. It
   refuses to run while `dev` is behind `main`, then opens `chore(promote): dev to
   main` whose description lists every change.
6. A human reviews the promotion (the diff is everything since the last promotion) and
   squash merges it.
7. release-please opens or updates the release pull request on `main`. A human merges
   it. The tag and the GitHub Release appear within a minute.
8. The release workflow merges `main` back into `dev`.

Branch names: `feat/add-logging`, `fix/iam-policy`, `docs/update-example`,
`chore/provider-update`. There is no `release/*` and no environment branch. A hotfix
that cannot wait for `dev` is a pull request from a short-lived branch straight into
`main`: approved by a human, released by release-please and merged back into `dev` by
the same sync as any other push to `main`. It is the exception, and an agent never
opens one.

The integration branch costs one more pull request per release and a sync that has to
stay healthy. `scripts/promote.sh` makes the sync a precondition rather than a memory
exercise, and the release workflow performs it.

Diagram: [`docs/diagrams/release-flow.png`](diagrams/release-flow.png) (the flow, the
promotion description, the version rules and the tokens) and
[`docs/diagrams/governance.png`](diagrams/governance.png) (who may do what on which
branch, the three rulesets, and what the plan enforces). Both pages are in
[`docs/diagrams/branching-and-release.drawio`](diagrams/branching-and-release.drawio).

The model applies to module repositories and to the root configurations that consume
them. `terraform-module-standards` and `terraform-aws-module-template` release nothing
and are consumed at `@main` or by copy, so they keep a single `main` and take pull
requests into it directly.

## 4. Conventional Commits

The pull-request title is the commit message that lands on `main` (section 13), so
the title must follow this form:

```text
<type>[optional scope][!]: <description>
```

| Type | Use for | Release effect |
| --- | --- | --- |
| `feat` | New capability: a new input, output or optional resource | Minor |
| `fix` | A bug fix | Patch |
| `docs` | Documentation only | None |
| `chore` | Maintenance: dependency bumps, tooling | None |
| `refactor` | Internal change with no behaviour change | None |
| `test` | Tests only | None |
| `ci` | CI and workflow changes | None |
| `revert` | Reverting an earlier change | Patch |

A commit with `!` after the type, or a `BREAKING CHANGE:` footer in the body, makes
the next release a major one, whatever the type.

```text
feat: add support for a customer managed KMS key
fix: correct the IAM policy condition for cross-account pull
docs: add a private subnet example
chore: raise the tflint-ruleset-aws plugin to 0.49.0
feat!: remove the deprecated repository_name input
```

```text
feat!: remove the deprecated repository_name input

Callers must rename repository_name to name.

BREAKING CHANGE: the repository_name input has been removed; use name.
```

Only `feat`, `fix` and breaking changes produce a release. A `docs` or `chore` commit
waits on `main` and ships with the next release that does.

## 5. Versioning

Semantic versioning, tags `vMAJOR.MINOR.PATCH`. release-please computes the number;
nobody types it.

| Release | Bump | Terraform examples |
| --- | --- | --- |
| **Patch** `v1.2.0 → v1.2.1` | `fix` | A `validation` regex rejected a valid name. A description was wrong. A missing `depends_on` caused an apply-time race. An IAM policy lacked an action the module's own resource needs. The plan for a correctly configured caller does not change, or changes only to repair the defect |
| **Minor** `v1.2.1 → v1.3.0` | `feat` | A new optional input with a default that keeps today's behaviour (`kms_key_arn = null`). A new output. A new resource behind a flag that defaults to off (`create_repository_policy = false`). Support for a newer provider without raising the minimum |
| **Major** `v1.3.0 → v2.0.0` | `!` or `BREAKING CHANGE` | An input or output removed or renamed. A default changed so existing callers' resources change (`image_tag_mutability` flipping to `MUTABLE`). A resource renamed, even with a `moved` block. Anything that makes a caller's plan replace a resource. A higher minimum Terraform or provider version. A `moved` block removed |

When in doubt: if a caller who upgrades without reading the changelog could see a
plan they did not expect, it is major.

## 6. Releases with release-please

```text
promotion pull request (or a hotfix) squash merged into main
      │
      ▼
release-please reads the Conventional Commits since the last tag
      │
      ▼
opens or updates one pull request: "chore(main): release X.Y.Z"
   (CHANGELOG.md, README version, .release-please-manifest.json)
      │
      ▼
a code owner reviews and merges that pull request
      │
      ▼
release-please creates tag vX.Y.Z and the GitHub Release with the changelog entry
```

Each module repository holds two small files.

`release-please-config.json`:

```json
{
  "$schema": "https://raw.githubusercontent.com/googleapis/release-please/main/schemas/config.json",
  "include-component-in-tag": false,
  "include-v-in-tag": true,
  "packages": {
    ".": {
      "release-type": "terraform-module",
      "changelog-path": "CHANGELOG.md",
      "extra-files": ["README.md"]
    }
  }
}
```

`.release-please-manifest.json`:

```json
{}
```

Facts the configuration relies on, checked against release-please's source:

- `release-type: terraform-module` updates `CHANGELOG.md`, replaces the first
  `version = "~> X.Y"` in `README.md` (a registry-style pin) and every `vX.Y.Z` string
  in `versions.tf`. Our modules use Git sources and have neither string, so those two
  updaters are inert. Keep it that way: no `~>` text in the README and no `vX.Y.Z` in
  `versions.tf`. The compliance check enforces both.
- `extra-files: ["README.md"]` makes release-please update any line in the README that
  ends with the comment `# x-release-please-version`. That is how the `?ref=vX.Y.Z`
  in the usage example tracks the current release.
- The `terraform-module` strategy starts at `0.1.0` and ignores `initial-version`.
  The first release is made `1.0.0` by ending the first pull request's description
  with the line `Release-As: 1.0.0` (procedure in [release.md](runbooks/release.md)).
- The manifest starts empty. release-please writes the released version into it.
- release-please runs as a GitHub App, not as `GITHUB_TOKEN`. A pull request opened
  with `GITHUB_TOKEN` never triggers the CI workflow, so the release PR could never
  pass the required status check. The App needs Contents, Pull requests and Issues
  read/write, and is installed once per organisation.
- `terraform-release.yml` passes `target-branch: main` to release-please-action
  explicitly. Left out, the action uses the repository's default branch; `main` is the
  release branch whatever the default branch is. The job also runs only when the
  caller was triggered on `refs/heads/main`.
- release-please walks `main`'s history in commit-date order and stops at the first
  commit whose SHA is the last release's. A merge commit from `dev` would leave every
  `dev` commit dated before that release unread, silently
  (googleapis/release-please#1533, #2883). The promotion is therefore a squash whose
  description lists every change (section 13).
- The release job runs in a concurrency group per repository and is never cancelled,
  so two pushes to `main` cannot both try to create the same tag. A failed run is
  rerun from the Actions tab or with `gh workflow run release-please.yml --ref main`;
  release-please is idempotent (labels `autorelease: pending` → `autorelease: tagged`).
- After every push to `main`, the `sync dev with main` job of the same workflow merges
  `main` into `dev` as the release App. The merge adds nothing `dev` has not already
  reviewed: the promotion squash commit and the release commit. If it conflicts, the
  job fails and names the fix (open a pull request from `main` into `dev`).

The release pull request can be edited before merging: its description becomes the
changelog entry and the release notes. Use that to add migration notes for a major
release.

## 7. Consuming a module

Pin an immutable release. Never reference `main`.

```hcl
module "ecr_repository" {
  source = "git::https://github.com/OWNER/terraform-aws-ecr-repository.git?ref=v1.2.0"

  name = "team/service"
}
```

| Case | Pin |
| --- | --- |
| Inside the organisation; release tags protected by the tag ruleset | `?ref=v1.2.0` |
| Tags not protected (private repository on GitHub Free), or the consumer is outside the organisation | `?ref=<40-character commit SHA>` with `# v1.2.0` on the line above |
| SSH access | `git::ssh://git@github.com/OWNER/terraform-aws-ecr-repository.git?ref=v1.2.0` |

Terraform fetches module code only during `terraform init`. The `version` argument
works only for registry sources; for a Git source the pin is the `ref`. Do not combine
`depth=1` with a SHA. Consuming repositories add the `terraform` ecosystem to their
`dependabot.yml` so Dependabot opens the upgrade pull request when a new tag appears.

Registry alternatives, evaluated:

| Option | Verdict |
| --- | --- |
| Git tag source (this standard) | **Use now.** No extra platform, works for private repositories, Dependabot understands it |
| Public Terraform Registry | Use when modules are public. Requires public repositories, the `terraform-<provider>-<name>` name and the Registry's GitHub app. Gives `version = "~> 1.0"` pins and a browsable UI; release-please's README updater then does exactly the right thing |
| HCP Terraform private registry | Not now. Adds a platform the organisation does not otherwise run |

## 8. Pull-request CI

Every module repository's `ci.yml` calls the shared workflow
[`terraform-ci.yml`](../.github/workflows/terraform-ci.yml) on pull requests, pushes to
`main` and once a week.

| Job | Runs | Catches |
| --- | --- | --- |
| PR title | `amannn/action-semantic-pull-request` | A title release-please cannot read |
| Test (oldest supported Terraform) and Test (latest) | `terraform fmt -check`, `init -backend=false`, `validate` for the module and every example, `terraform test` | Syntax, type and logic errors on both ends of the supported range |
| Lint | `tflint --recursive` with the `terraform` and `aws` rulesets | Deprecated syntax, unused declarations, invalid AWS arguments |
| Docs | `terraform-docs` with `fail-on-diff`, then markdownlint on every Markdown file | Input and output tables that no longer match the code; broken Markdown in `docs/` |
| Provider floor (when `aws-provider-min-version` is set) | `terraform init` and `terraform test` with the AWS provider pinned to the declared minimum | A module that claims to work with an older provider but uses something newer |
| Security scan | Checkov, `framework: terraform` | Insecure defaults and misconfigurations. The module repository is the only place the module's resources are scanned |
| CI passed | Aggregates the jobs above | The one status check the ruleset requires: `ci / CI passed` |

The weekly scheduled run tests against the latest Terraform and the latest provider
release, so a breaking upstream release is noticed before it blocks a real change.

Not run, on purpose: Trivy and tfsec (the same misconfiguration checks as Checkov),
`terraform plan` against a real account (the mocked tests need no credentials and
create nothing), CodeQL (no application code). Module-specific Checkov exceptions are
passed as the `checkov-skip-checks` input and justified in the module's README.

## 9. Terraform and provider versions

```hcl
terraform {
  # Minimum versions only. The root configuration that calls the module sets
  # upper bounds. 1.9 is the first version whose variable validation can refer
  # to other variables.
  required_version = ">= 1.9.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0"
    }
  }
}
```

- A module declares the **lowest** version it actually works with and no upper bound.
  New modules start at Terraform `>= 1.9.0` and `hashicorp/aws >= 6.0`; a module goes
  higher only when it uses something newer, with a comment saying what (for example
  `terraform-aws-vpc` needs aws 6.24 for regional NAT gateways). An existing module
  keeps its floor until it needs more (`terraform-aws-ecr-repository` works from
  Terraform 1.7 and aws 5.0). Raising either minimum is a major release.
- CI tests the newest patch of the oldest allowed minor (the `terraform-min-version`
  input, `1.9.8` for `>= 1.9.0`) and `latest`; with `aws-provider-min-version` set it
  also tests the provider floor.
- Supporting providers (`random`, `null`, `archive`) follow the same rule, and a
  module declares only providers it uses.
- Examples carry their own `versions.tf` with the same minimums.

**Lock files are not committed in module repositories.** `.terraform.lock.hcl`
records the provider versions one `init` selected. A module declares a range, and CI
must test both ends of it; a committed lock file would pin every job to one version
and tell consumers nothing, because Terraform ignores a module's lock file. Consuming
root configurations commit their lock file as usual.

### Version baseline (checked 2026-10-16)

The current releases, from the HashiCorp registry, the Terraform checkpoint API and
each project's GitHub releases. Recheck before raising a floor; never copy these into
a module as upper bounds.

| Component | Current | Used where |
| --- | --- | --- |
| Terraform | 1.16.6 | CI `latest`; consumers' roots |
| Terraform floor for new modules | 1.9 (CI tests 1.9.8) | `required_version` |
| `hashicorp/aws` | 6.69.1 | CI `latest`; floor `>= 6.0` unless a feature needs more |
| `hashicorp/random`, `null`, `archive` | 3.9.1, 3.3.2, 2.8.1 | only where used |
| TFLint / `tflint-ruleset-aws` | 0.64.0 / 0.49.0 | shared CI, `.tflint.hcl` |
| Checkov | 3.3.26 (`checkov-action` v12.3131.0, as pinned; Dependabot proposes newer tags) | shared CI |
| terraform-docs | 0.24.0 (release binary, checksum checked in the shared workflow) | shared CI, pre-commit |
| release-please | 17.6.0, bundled in `release-please-action` v5.0.0, the newest Action release (release-please itself is at 17.11.2) | shared release workflow |

Terraform features the modules use, and the version that introduced each:
`moved` (1.1), preconditions and postconditions (1.2), `optional()` attributes with
defaults (1.3), `terraform test` (1.6), `mock_provider` and `removed` (1.7),
cross-variable validation (1.9). Newer features that matter to consumers rather than
modules: `import` blocks inside modules (1.16) and `lifecycle { destroy = false }`
(1.16); `deprecated` on variables and outputs (1.15) is the right way to retire an
input in a minor release before removing it in a major one, once module floors reach
1.15.

## 10. Security

| Control | How |
| --- | --- |
| Secret scanning and push protection | Repository setting, applied by the bootstrap script. Free on public repositories; private ones need GitHub Secret Protection |
| Dependabot alerts and security updates | Repository settings, applied by the bootstrap script |
| CODEOWNERS | Section 11; review required by the ruleset |
| Least-privilege Actions | Every workflow declares `permissions`. The shared CI jobs hold `contents: read`; the release job holds nothing of its own and acts through the App token |
| Pinned actions | Every `uses:` names a full commit SHA with the version as a comment. Dependabot keeps them current |
| OIDC, no long-lived AWS keys | Module CI needs no AWS access at all. Where a consumer or an optional integration test does, it assumes a role through GitHub's OIDC provider (`aws-actions/configure-aws-credentials` with `role-to-assume` and `id-token: write`). No AWS access key is ever a repository secret |
| No secrets in Terraform | Inputs that carry secrets are `sensitive = true`; values arrive from Secrets Manager or `TF_VAR_*`, never from committed files. `.gitignore` excludes `*.tfvars`, state and plan files |
| Protected `dev`, `main` and tags | Section 12 |
| Promotion is human | A maintainer opens the `dev → main` pull request (`scripts/promote.sh`) and a different human approves it. Agents hold no admin role and no bypass, and open pull requests into `dev` only |
| Required CI | The ruleset requires `ci / CI passed` |
| Release identity | A GitHub App with Contents, Pull requests and Issues read/write, installed on module repositories only. Its private key is an organisation secret, or a repository secret where the plan does not allow organisation secrets on private repositories |
| Read access for consumers' CI | A second GitHub App with Contents read-only, installed on module repositories, minted per job with `actions/create-github-app-token`. Never a token in a `source` URL |

## 11. CODEOWNERS

```text
# Every change needs a review from the owning team.
* @OWNER/TEAM
```

Teams, not people: a person leaves, a team is updated. The team needs write (or
maintain) access to the repository, or GitHub ignores the line. Add a second line only
when a different team genuinely owns part of the module, for example
`/examples/ @OWNER/solutions`. The compliance check calls GitHub's CODEOWNERS
validation endpoint.

Until the owning team exists, the file holds only the comment and no rule. The
compliance check then warns instead of failing, and `new-module-repo.sh --team` adds
the rule when the team is known.

## 12. Repository rulesets

Three rulesets, identical in every module repository, imported from
[`rulesets/`](../rulesets/) by the bootstrap script. `main.json` targets
`refs/heads/main` by name, not the default branch, so changing the default branch
never moves the release rules.

| Ruleset | Rule | Setting |
| --- | --- | --- |
| `dev` | Require a pull request | 1 approving review, stale reviews dismissed on push, approval of the most recent push, conversation resolution required, squash is the only merge method |
| `dev` | Required status checks | `ci / CI passed`; the branch need not be up to date (an integration branch moves too fast for that) |
| `dev` | Block deletion and force-push | On |
| `dev` | Bypass | The release App, always: it pushes the `main → dev` sync. Organisation owners, pull-request mode (see below) |
| `main` | Require a pull request | 1 approving review, stale reviews dismissed on push, code owner review required, approval of the most recent push, conversation resolution required, squash is the only merge method |
| `main` | Required status checks | `ci / CI passed`, branch must be up to date |
| `main` | Block deletion and force-push | On |
| `main` | Linear history | On (squash merges make it so) |
| `main` | Bypass | Organisation owners, pull-request mode only. Nobody bypasses on a direct push |
| `release tags` (`refs/tags/v*`) | Block creation, deletion, update and force-push | On. The release App is the only bypass actor, so release-please is the only thing that can create a release tag |

The bootstrap script replaces the placeholder `actor_id: 0` with the release App's ID
(the `Integration` actor; GitHub's documentation does not say which ID the type expects,
so read the ruleset back after the first import and correct the file if needed). The
organisation-owner bypass in pull-request mode exists for an organisation with one
maintainer, who could otherwise never merge their own pull request: a bypass merge is
recorded as such in the audit log. `OrganizationAdmin` is used rather than a repository
role because GitHub documents it (the `actor_id` is ignored) and does not document the
repository-role IDs. Remove it from both files as soon as a second maintainer exists.
AI agents are never organisation owners, so the bypass is not open to them.

Plan constraints, as GitHub documents them:

- Rulesets, CODEOWNERS enforcement and branch protection work on **public**
  repositories on every plan, and on private repositories only on GitHub Pro, Team or
  Enterprise. On GitHub Free the API refuses a ruleset on a private repository
  ("Upgrade to GitHub Pro or make this repository public to enable this feature"),
  so nothing protects `dev`, `main` or the tags, and the model in section 3 is
  procedural until that changes. Decide visibility, or the plan, before the first
  module repository is created
  ([create-repository.md](runbooks/create-repository.md), step 0).
- Organisation-level rulesets need GitHub Team or Enterprise. When the organisation
  is on such a plan, import the same three files once at organisation level, targeting
  repositories named `terraform-aws-*`, and stop importing them per repository. The
  `rulesets` recipes repository already has the tooling (`make deploy`).
- Tag name patterns need Enterprise. Tag names are enforced by release-please
  creating them instead.

## 13. Merge strategy

**Into `dev`: squash merge only.** The repository settings make the squash commit's
subject the pull-request title and its body the pull-request description.

```text
PR title:  feat: add support for a customer managed KMS key
PR body:   Adds kms_key_arn ...
           ...
           BREAKING CHANGE: ... (only if there is one)
           Release-As: 1.0.0   (first release only)
```

- release-please reads the squash commit. The title decides the version bump; a
  `BREAKING CHANGE:` footer in the body adds a breaking-changes section to the
  changelog; a `Release-As:` footer overrides the version.
- The PR title check in CI rejects a title that is not a Conventional Commit, so a
  bad title never reaches `main`.
- Local commit messages on the branch do not matter. They disappear in the squash.
- release-please also treats any line near the end of the body that itself looks like
  a Conventional Commit (`fix: ...`) as an extra changelog entry. Write the body in
  prose; do not paste commit lists into it.

**Into `main`: squash merge of the promotion pull request, with the generated
description.** `scripts/promote.sh` writes the description from the squash commits on
`dev` that `main` lacks: one block per change, oldest first, holding the subject
(`feat(aurora): add serverless v2 scaling (#10)`) and, directly under it, that commit's
`BREAKING CHANGE:` and `Release-As:` footers if any. Every header starts at column 0,
blocks are separated by blank lines, nothing is bulleted. release-please parses each
block as its own change (its README: "What if my PR contains multiple fixes or
features?"), so one squash commit on `main` releases exactly what `dev` accumulated,
with the right bump, while the title `chore(promote): dev to main` adds nothing to the
changelog. The reviewer reads the same list.

```text
chore(promote): dev to main (#42)

Promotes 3 change(s) from dev to main. Squash merge only. ...

feat(aurora): add serverless v2 scaling (#10)

fix(vpc): correct the private NAT route (#11)
BREAKING CHANGE: route table ids are renamed

feat: add the sns-alert-topic module (#1)
Release-As: 1.0.0
```

Why not a merge commit: release-please reads `main` in commit-date order and stops at
the first commit equal to the last release. A merge commit keeps `dev`'s commits with
their original dates, so any of them older than the last release commit is skipped
without a warning (googleapis/release-please#1533 and #2883; the maintainers: "this is
one of the main reasons we avoid using merge commits"). Why not rebase: it rewrites
SHAs, drops signatures, and release-please can no longer match the commits to their
pull requests.

**Into `dev` from `main`: the sync job pushes a merge commit** as the release App. Its
content is what `dev` already reviewed plus the release commit. Nothing else ever
reaches `dev` by merge commit.

If a promotion was merged with a wrong description, edit the merged pull request's
description and add a `BEGIN_COMMIT_OVERRIDE … END_COMMIT_OVERRIDE` block listing the
changes in the same shape; release-please uses it on its next run. This works for
squash merges only.

Merge commits and rebase merges are disabled in the repository settings for pull
requests. The sync job's merge commit arrives by `git push`, which those settings do
not govern.

## 14. Dependency updates

| Dependency | How it is updated | Gate before merge |
| --- | --- | --- |
| GitHub Actions (SHA pins) | Dependabot, weekly, grouped, `ci:` prefix, with a seven-day cooldown so a release is a week old before it is proposed, in every module repository and in `terraform-module-standards`. Version updates target `dev` (`target-branch: dev`); Dependabot security updates always target the default branch, `main`, and are merged back into `dev` by the sync | The full CI run on the Dependabot pull request |
| Terraform CLI | CI tests `latest` every week; `terraform-min-version` is raised deliberately in a `feat!:` pull request | CI on both matrix entries |
| AWS provider | No upper bound; CI tests the latest weekly. A new minimum is a `feat!:` pull request | CI, including Checkov and tests |
| TFLint and its AWS ruleset | Versions live in the shared workflow and in the template's `.tflint.hcl`. Bump centrally; the compliance check reports modules whose `.tflint.hcl` drifted | Standards repository CI, then each module's next run |
| Checkov, setup actions | Pinned by SHA in the shared workflow; Dependabot bumps them there | Standards repository CI |
| terraform-docs | Version and SHA-256 in the shared workflow's Docs job. Dependabot cannot see them: bump both by hand when a release appears | Standards repository CI |
| pre-commit hooks | `pre-commit autoupdate` in the template, monthly, copied to modules when they next change | Local run |

Every update still goes through `fmt`, `validate`, `lint`, `security` and `tests`,
because every update is a pull request.

## 15. Module README

The README is the front page: what the module is, how to call it, and where to read
more. Depth lives in `docs/` (section 2). Sections, in order. Inputs, outputs,
requirements and resources are generated by `terraform-docs` between
`<!-- BEGIN_TF_DOCS -->` and `<!-- END_TF_DOCS -->`; CI fails when they are stale.

1. Title and one paragraph: what the module creates and for whom.
2. What it does not manage (account-wide settings, IAM identities, provider and state).
3. Usage: one pinned Git source call, the `?ref=` line annotated
   `# x-release-please-version`.
4. Examples: a table linking `examples/basic` and `examples/complete`.
5. Documentation: a table linking the four `docs/` pages by the reader's need.
6. The generated block: requirements, providers, resources, inputs, outputs.
7. Defaults and security decisions: a table of each secure default, why, and the input
   that changes it.
8. Security scanning: any Checkov check skipped, and why.
9. Upgrading: what each major version requires.
10. Versioning and releases: a few lines linking to this standard.
11. Contributing and ownership: links to `CONTRIBUTING.md`, `CODEOWNERS` and
    `SECURITY.md`.

A README longer than about 300 lines is a sign the module does too much.

## 16. Reusable template and central workflows

```text
Create repository (from template)  ──>  bootstrap script applies settings + rulesets  ──>  add Terraform code  ──>  ready
```

| Mechanism | Used for | Verdict |
| --- | --- | --- |
| GitHub template repository (`terraform-aws-module-template`) | Every file in section 2, with `__OWNER__`, `__TEAM__`, `__MODULE__` placeholders | **Yes.** One click or one `gh repo create --template` |
| Reusable workflows (`terraform-ci.yml`, `terraform-release.yml`) | All CI logic, tool versions, action pins | **Yes.** Module repositories keep two thin callers. A change to the standard is one pull request, reviewed once |
| Bootstrap script (`scripts/new-module-repo.sh`) | Settings, topics, team access, rulesets, secrets, placeholder substitution | **Yes.** Idempotent; `--configure-only` upgrades an existing repository |
| Compliance script (`scripts/check-module-repo.sh`) | Proves a repository meets sections 2, 3, 6, 9, 11, 12 and 13 | **Yes.** Local and remote checks |
| Promotion script (`scripts/promote.sh`) | Opens the `dev → main` pull request with the description release-please needs; refuses while `dev` is behind `main` | **Yes.** The one step in the model that a person performs by hand |
| Organisation rulesets | The three rulesets, applied once | **When the plan allows** (Team or Enterprise). Until then the script imports them per repository |
| Composite actions | Wrapping individual steps | **No.** The reusable workflows already remove the duplication |
| Central CODEOWNERS | One file for all repositories | **Not possible.** GitHub has no such mechanism; the standard team name is the substitute |

Module repositories call the shared workflows at `@main`. The standards repository
is protected by the same ruleset, so a change to the workflows is reviewed once and
reaches every module at once, which is the point of central standards. A repository
that needs to hold back can pin a commit SHA of the standards repository instead.

Central: workflow logic, action and tool versions, rulesets, runbooks. Local: the
module code, `terraform-min-version`, Checkov exceptions, `.tflint.hcl`,
`.terraform-docs.yml`, release-please state.

## 17. Minimum standard and compliance

Every module repository has:

```text
README.md  LICENSE  CONTRIBUTING.md  CHANGELOG.md  SECURITY.md  .github/CODEOWNERS
versions.tf (minimums only)   examples/basic/  examples/complete/   tests/*.tftest.hcl
docs/{tutorials,how-to,reference,explanation}/
ci.yml and release-please.yml calling the shared workflows
release-please-config.json (terraform-module)   .release-please-manifest.json
branches dev and main   squash-only merges   the three rulesets   semantic version tags
```

`scripts/check-module-repo.sh PATH --repo OWNER/NAME` checks all of it and exits
non-zero on a failure. Run it after bootstrap, after migrating a module, and whenever
the standard changes. That is the whole governance: one script, one standard, one
template.

## 18. Documentation style

British English. Active voice. Short sentences. Copy-and-paste-ready commands with the
variables set at the top. A diagram only where the order of events matters. Every
runbook has the same six headings: Purpose, Prerequisites, Steps, Validation,
Rollback, Troubleshooting.

## 19. What becomes a shared module

A module earns its own repository only when it is a **capability** another team
would call unchanged. Before extracting one, or adding an input to one, answer:

1. Is it commonly needed, by more than one project?
2. Does it make reuse easier than copying?
3. Does it keep a secure default?
4. Does it hide complexity a caller would otherwise get wrong?
5. Would the native resource be simpler? If yes, do not build the module.

| Keep in the project | Make a shared module |
| --- | --- |
| Anything that encodes one application's contract: its secrets, environment variables, alarm thresholds, content policies, pipelines | A resource family with a well-known shape and secure defaults that are easy to get wrong: network, database cluster, bucket, repository, encrypted alert topic, SSM-only instance |
| Glue: provisioners that read the project's own files, cross-module wiring, naming conventions | The resources themselves, named from a `name` input |
| Thin wrappers around one resource with nothing to default (IAM role, log group, single alarm) | |

A module has one responsibility. It takes a `name` and `tags`, never a project or
environment input, and never decides naming conventions beyond `<name>-<suffix>`.
Permissions a caller needs on top of what the module's resources require are composed
by the caller (attach a policy to the role the module outputs); a module does not take
free-form policy documents for its own roles. Organisation-wide tags belong in the
caller's provider `default_tags`; a module's `tags` input is for resource-specific
tags.
