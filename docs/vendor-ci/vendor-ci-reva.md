# Reva and CERNBox OCM CI plugin

This page shows how to run the OCM Test Suite as a GitHub Actions job in a Reva or CERNBox repo.

The workflow builds a Reva binary from the current branch, then runs a small invite-link matrix through the `dev-stock` image and shows the results in a summary table.

## Matrix

The matrix covers these invite-link combinations:

1. `Stub v1.1.0` <-> `Stub v1.1.0`
2. `Stub v1.1.0` <-> `CERNBox (current Reva build)`
3. `CERNBox (current Reva build)` <-> `Stub v1.1.0`
4. `CERNBox (current Reva build)` <-> `CERNBox (current Reva build)`

Notes:

- Stub uses the OCM Stub v1.1.0 image for invite-link scenarios.
- CERNBox uses a `revad` binary built from the branch or PR that triggered the workflow.

## Jobs

A minimal workflow has three jobs.

### 1. `ocm-prepare`

- Checks out the Reva repo.
- Computes a version string (for example from a `VERSION` file) or falls back to `dev`.
- Exposes that value as `CURRENT_VERSION` for later jobs.

### 2. `ocm-build-revad`

- Needs `ocm-prepare`.
- Builds a static `revad` binary from the current branch (for example using `gaia`).
- Uploads the binary as an artifact named `revad-binary`.

### 3. `ocm-actors` (matrix job)

- Needs `ocm-prepare` and `ocm-build-revad`.
- Runs on `ubuntu-latest` with:
  - `continue-on-error: true`
  - `strategy.fail-fast: false`
- Defines a matrix with four entries. Each entry includes:
  - `combo_id` (for example `stub-stub`, `stub-cernbox`).
  - `display_name` (label shown in the Actions UI).
  - `sender`, `sender_version` (`ocmstub` or `cernbox`, version `v1.1.0` or `v2`).
  - `receiver`, `receiver_version`.
  - `requires_reva_binary` (true when that combo needs the current `revad`).
  - `images`: multi-line list of Docker images to pull for this combo.

Each matrix run typically does the following:

1. Create a small directory tree under the workspace (for example `.ocm-dev-stock-root/`) and symlink it to `/dev-stock`.
2. Loop over `matrix.images` and `docker pull` each non-empty line.
3. When `requires_reva_binary` is true:
   - Download the `revad-binary` artifact with `actions/download-artifact@v4`.
   - Place it under `.ocm-dev-stock-root/reva-binaries/cmd` and `chmod +x` it.
4. Run the OCM Test Suite via the `dev-stock` image:
   - Set `REVA_BINARY_DIR` to the directory where the `revad` binary was placed when needed.
   - Run `docker run` with:
     - `--entrypoint ocm-test-suite`
     - `-v /var/run/docker.sock:/var/run/docker.sock`
     - `-e CI_ENVIRONMENT=true`
     - Optionally `-e DEVSTOCK_DEBUG=true` while iterating.
     - Arguments: `invite-link <sender> <sender_version> ci electron <receiver> <receiver_version>`
5. Capture the result as a small JSON file like `{ "combo_id": "stub-cernbox", "status": "pass" }` and upload it as `ocm-matrix-status-<combo_id>`.
6. Upload Cypress videos and screenshots as `cypress-<combo_id>`.

Because the job uses `continue-on-error: true`, all four combos try to run even if some fail.

## Summary job

The `ocm-summary` job reads the status artifacts and builds a compact overview.

- Needs `ocm-prepare` and `ocm-actors`.
- Runs with `if: always()`.
- Requires `permissions: actions: write`.

Typical steps:

1. Install `jq`.
2. Download all `ocm-matrix-status-*` artifacts to a temporary directory.
3. For each combo id (`stub-stub`, `stub-cernbox`, `cernbox-stub`, `cernbox-cernbox`):
   - Read `status.json` with `jq` if it exists, otherwise treat status as `UNKNOWN`.
4. Append a small Markdown table to `$GITHUB_STEP_SUMMARY`:
   - Combination label.
   - Scenario (`invite-link`).
   - Status.
   - Link or name for `cypress-<combo_id>`.
5. Call `geekyeggo/delete-artifact@v5` with `name: ocm-matrix-status-*` and `failOnError: false` to clean up the status artifacts only.

The summary job must not delete `revad-binary` or any `cypress-*` artifacts.

## How to adopt this in a Reva or CERNBox repo

1. Add a workflow file similar to the one described above under `.github/workflows/ocm-test-suite.yml`.
2. Make sure your runners can use Docker and can bind-mount `/var/run/docker.sock` into the `dev-stock` container.
3. Confirm that the `ocm-build-revad` job produces a working `revad` binary and that `REVA_BINARY_DIR` is passed correctly into the `dev-stock` container.
4. Run the workflow manually (`workflow_dispatch`) on a test branch and verify:
   - All four matrix entries appear and run.
   - The job summary shows a table with one row per combination.
   - `cypress-<combo_id>` artifacts contain videos and screenshots for failing combos.
5. Once you are happy with the results, enable the workflow on pull requests and main branch pushes so that OCM coverage is part of your regular CI.
