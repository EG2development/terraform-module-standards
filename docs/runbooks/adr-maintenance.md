# Review decision records with Copilot code review

## Purpose

Every module repository records its architecture decisions in `docs/decisions/`, under
the policy in that directory's README and from its `adr-template.md`. Copilot code
review checks each pull request against them by following one instruction file,
`.github/instructions/adr-review.instructions.md`. There is no workflow, script or
custom agent. This runbook turns the review on and checks that it works.

| Who | Does |
| --- | --- |
| Copilot code review | Comments when a change needs a record the pull request does not add, and when a record differs from the policy or the template; suggests one-line fixes. It never commits, approves or accepts a record |
| The pull-request author | Writes or updates the record from `adr-template.md` |
| A human reviewer | Decides whether the record is right, sets `status: "accepted"` and the date, approves and merges |

## Prerequisites

- Copilot code review for the people who open pull requests: a Copilot Pro, Pro+, Max,
  Business or Enterprise licence, or the organisation's AI credits.
- `docs/decisions/README.md` and `adr-template.md` in the module (standard, section 2).
- Permission to manage the repository's or the organisation's rulesets, for step 3.
- Variable: `MODULE_DIR`, a clone of the module.

## Steps

1. Copy the instruction file from the template. It is identical in every module.

   ```bash
   cd "$MODULE_DIR"
   mkdir -p .github/instructions
   cp ../terraform-aws-module-template/.github/instructions/adr-review.instructions.md .github/instructions/
   ```

2. Open a pull request titled `docs: review decision records with Copilot` and merge it.
   Copilot reads instructions from the pull request's head branch, so it applies the
   file to the pull request that adds it.
3. Request Copilot's review on every pull request. In the repository's settings, open
   Rulesets and choose New ruleset, then New branch ruleset. Target the default branch,
   select *Automatically request Copilot code review*, and optionally *Review new
   pushes*. For all modules at once, create the same ruleset in the organisation's
   settings with the repository pattern `terraform-aws-*`.
4. Keep custom instructions on for code review: Settings, Copilot, Code review.

## Validation

Open three throwaway pull requests in the module and read Copilot's review of each:

| Pull request | Expected review |
| --- | --- |
| Change a default, for example narrow an egress default, with no record | A comment on the changed line asking for a record, naming what it must state; questions if the description gives no reason |
| Add a record named `adr-1.md` with no `## More Information` section and no index row | Comments on the filename, the missing section and the missing row |
| Reword a variable description | No comment about decision records |

Close them without merging.

## Rollback

Delete `.github/instructions/adr-review.instructions.md` and turn off the ruleset rule.
Records already in `docs/decisions/` stay where they are.

## Troubleshooting

| Symptom | Cause | Fix |
| --- | --- | --- |
| Copilot's review never mentions decision records | Copilot was not requested, custom instructions are off for code review, or the file is not on the head branch | Request Copilot as a reviewer or enable the ruleset rule; check step 4; the file must sit under `.github/instructions/` and end in `.instructions.md` |
| No review at all | The author has no Copilot licence and the organisation does not pay, or the budget is spent | Check the organisation's Copilot code review billing settings |
| Copilot asks for a record for a routine change | The list in the instruction file let it through | Reply on the comment and resolve it. If it recurs, tighten the list in the template's file and copy it to every module |
| Copilot asks for a record that exists | The record does not link the pull request and its subject is not evident from the diff | Link the pull request under `## More Information` |
| A review in VS Code or Visual Studio ignores the file | Those IDE reviews read only `.github/copilot-instructions.md` | The check is meant for pull requests on GitHub |
| The policy changed and Copilot still checks the old rule | Code review does not follow links; the instruction file restates the policy | Change the file in the same pull request as `docs/decisions/README.md` |
