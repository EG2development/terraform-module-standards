# Runbooks

Every runbook has the same six headings: Purpose, Prerequisites, Steps, Validation,
Rollback, Troubleshooting. Set the variables at the top of a runbook once, then paste
the commands.

| Runbook | Use it when |
| --- | --- |
| [create-repository.md](create-repository.md) | You are creating a new module repository, or setting up the organisation for the first time |
| [developer-workflow.md](developer-workflow.md) | You are changing a module. The daily cheat sheet |
| [promote-to-main.md](promote-to-main.md) | `dev` holds what should ship: open and merge the promotion pull request |
| [release.md](release.md) | A promotion has merged and a release pull request is waiting, or you want to know why there is none. Includes the first release |
| [breaking-change.md](breaking-change.md) | A change removes or renames an input, changes a default, or replaces a resource |
| [migrate-existing-module.md](migrate-existing-module.md) | A module living inside a project repository is moving to its own repository |
| [upgrade-module-version.md](upgrade-module-version.md) | A consuming repository is moving to a newer module version |
| [troubleshooting.md](troubleshooting.md) | Something in CI, release-please or `terraform init` is not behaving |

The rules behind the runbooks are in [the standard](../standard.md).
