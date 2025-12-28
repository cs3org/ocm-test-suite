# Nextcloud OCM CI plugin

This page shows how to run the OCM Test Suite as a GitHub Actions job in a Nextcloud server repo.

The idea is simple:

- One workflow file (for example `.github/workflows/ocm-test-suite.yml`).
- One matrix job that always runs four `share-with` combinations.
- One summary job that turns the results into a small table and links to Cypress artifacts.

## Matrix

The matrix covers these combinations:

1. `Stub v1` <-> `Stub v1`
2. `Stub v1` <-> `Nextcloud (current branch)`
3. `Nextcloud (current branch)` <-> `Stub v1`
4. `Nextcloud (current branch)` <-> `Nextcloud (current branch)`

Notes:

- Stub uses the OCM Stub v1.0.0 image for `share-with`.
- The Nextcloud side always uses the code from the branch or PR that triggered the workflow.

## Jobs

A minimal workflow has three jobs.

### 1. `ocm-prepare`

- Checks out the Nextcloud repo.
- Reads `version.php` and computes a version string like `v29.0.0`.
- Exposes that value as `CURRENT_VERSION` for later jobs.

### 2. `ocm-actors` (matrix job)

- Needs `ocm-prepare`.
- Runs on `ubuntu-latest` with:
  - `continue-on-error: true`
  - `strategy.fail-fast: false`
- Defines a matrix with four entries. Each entry includes:
  - `combo_id` (for example `stub-stub`, `stub-nextcloud`).
  - `display_name` (label shown in the Actions UI).
  - `sender`, `sender_version` (`ocmstub` or `nextcloud`, version `v1.0.0` or `current`).
  - `receiver`, `receiver_version`.
  - `uses_nextcloud_source` (true when that side needs the current repo).
  - `images`: multi-line list of Docker images to pull for this combo.

Each matrix run typically does the following:

1. Checkout the repo (for entries with `uses_nextcloud_source: true`).
2. Create a small directory tree under the workspace (for example `.ocm-dev-stock-root/`) and symlink it to `/dev-stock`.
3. Loop over `matrix.images` and `docker pull` each non-empty line.
4. Set `NEXTCLOUD_SOURCE_DIR` when needed and run the `dev-stock` image with:
   - `--entrypoint ocm-test-suite`
   - `-v /var/run/docker.sock:/var/run/docker.sock`
   - `-e CI_ENVIRONMENT=true`
   - Arguments: `share-with <sender> <sender_version> ci electron <receiver> <receiver_version>`
5. Capture the result as a small JSON file like `{ "combo_id": "stub-stub", "status": "pass" }` and upload it as `ocm-matrix-status-<combo_id>`.
6. Upload Cypress videos and screenshots as `cypress-<combo_id>`.

Because the job uses `continue-on-error: true`, all four combos try to run even if some fail.

### 3. `ocm-summary`

- Needs `ocm-prepare` and `ocm-actors`.
- Runs with `if: always()` so it still runs if some combos failed.
- Requires `permissions: actions: write` for artifact handling.

Typical steps:

1. Install `jq`.
2. Download all `ocm-matrix-status-*` artifacts to a temporary directory.
3. For each combo id (`stub-stub`, `stub-nextcloud`, `nextcloud-stub`, `nextcloud-nextcloud`):
   - Read `status.json` with `jq` if it exists, otherwise treat status as `UNKNOWN`.
4. Append a small Markdown table to `$GITHUB_STEP_SUMMARY`:
   - Combination label.
   - Scenario (`share-with`).
   - Status.
   - Link or name for `cypress-<combo_id>`.
5. Call `geekyeggo/delete-artifact@v5` with `name: ocm-matrix-status-*` and `failOnError: false` to clean up the status artifacts only.

The summary job must not delete any `cypress-*` artifacts.

## How to adopt this in a Nextcloud repo

1. Add a workflow file similar to the one described above under `.github/workflows/ocm-test-suite.yml`.
2. Make sure your runners can use Docker and can bind-mount `/var/run/docker.sock` into the `dev-stock` container.
3. Check that `version.php` parsing works and that the computed version matches what you expect.
4. Run the workflow manually (`workflow_dispatch`) on a test branch and verify:
   - All four matrix entries appear and run.
   - The job summary shows a table with one row per combination.
   - `cypress-<combo_id>` artifacts contain videos and screenshots for failing combos.
5. Once you are happy with the results, enable the workflow on pull requests and main branch pushes. This gives you a small but useful OCM regression test on every change.