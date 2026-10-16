# Contributing

1. Branch from `main`; one change per branch.
2. Pull-request title is a Conventional Commit: `feat:`, `fix:`, `docs:`, `chore:`, `ci:`.
3. `pre-commit run --all-files` passes locally (`pre-commit install` once).
4. One code owner approves; squash merge.

Changes to `.github/workflows/terraform-*.yml` affect every module repository on their
next CI run. Say so in the pull request and re-run CI on at least one module repository
before merging.
