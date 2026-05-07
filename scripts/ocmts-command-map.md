# ocmts command map

<!-- markdownlint-disable MD013 -->

Flat reference of every `nu scripts/ocmts.nu <domain> <verb>` form,
generated from `scripts/domains/*/mod.nu`. Run `nu scripts/ocmts.nu
<domain>` for the live per-domain help, which is always authoritative.

Run from the repo root.

## actors

| Command                                              | Purpose                                                           |
| ---------------------------------------------------- | ----------------------------------------------------------------- |
| `nu scripts/ocmts.nu actors list`                    | List scenarios enabled in the matrix SSOT.                        |
| `nu scripts/ocmts.nu actors list overrides`          | List scenarios with override files in `config/actors/scenarios/`. |
| `nu scripts/ocmts.nu actors show <scenario>`         | Show resolved actor record for a one-party scenario.              |
| `nu scripts/ocmts.nu actors validate <args>`         | Validate one scenario's resolution.                               |
| `nu scripts/ocmts.nu actors validate-all`            | Validate every matrix-enabled scenario.                           |

## artifacts

| Command                                                    | Purpose                                                        |
| ---------------------------------------------------------- | -------------------------------------------------------------- |
| `nu scripts/ocmts.nu artifacts list`                       | List artifact directories on disk.                             |
| `nu scripts/ocmts.nu artifacts show <run>`                 | Show one run's artifact tree summary.                          |
| `nu scripts/ocmts.nu artifacts collect ...`                | Collect post-run artifacts for one cell.                       |
| `nu scripts/ocmts.nu artifacts publish ...`                | Publish/copy artifacts to the publish target.                  |
| `nu scripts/ocmts.nu artifacts prune ...`                  | Prune old artifact directories.                                |
| `nu scripts/ocmts.nu artifacts optimize-media ...`         | Optimize raw cell media (images/video) into a smaller form.    |
| `nu scripts/ocmts.nu artifacts probe-optimizer`            | Probe the media optimizer image (pull/verify availability).    |
| `nu scripts/ocmts.nu artifacts aggregate-optimized-media ...` | Aggregate per-cell optimized media dirs into one summary.   |

## ci

| Command                                            | Purpose                                            |
| -------------------------------------------------- | -------------------------------------------------- |
| `nu scripts/ocmts.nu ci plan ...`                  | Plan a suite (cells, order, exec ids).             |
| `nu scripts/ocmts.nu ci workflows generate github` | Render GitHub workflow YAMLs from blueprints.      |
| `nu scripts/ocmts.nu ci workflows check github`    | Drift-check rendered workflows against blueprints. |
| `nu scripts/ocmts.nu ci aggregate ...`             | Aggregate per-cell suite manifests into one.       |
| `nu scripts/ocmts.nu ci emit-blocked ...`          | Emit a blocked-cell artifact set.                  |

## images

| Command                                    | Purpose                              |
| ------------------------------------------ | ------------------------------------ |
| `nu scripts/ocmts.nu images list [--json]` | List configured images.              |
| `nu scripts/ocmts.nu images show <id>`     | Show one image's resolved config.    |
| `nu scripts/ocmts.nu images resolve ...`   | Resolve image precedence for a cell. |

## matrix

| Command                                         | Purpose                                                                                         |
| ----------------------------------------------- | ----------------------------------------------------------------------------------------------- |
| `nu scripts/ocmts.nu matrix gen cypress`        | Regenerate `cypress/e2e/<flow>/matrix.ts` files.                                                |
| `nu scripts/ocmts.nu matrix list [--json]`      | List enabled cells.                                                                             |
| `nu scripts/ocmts.nu matrix cell ...`           | Show one cell record.                                                                           |
| `nu scripts/ocmts.nu matrix check capabilities` | Validate adapter capabilities SSOT against platforms, flows, registry, and public-site files.   |

## services

| Command                                    | Purpose                                |
| ------------------------------------------ | -------------------------------------- |
| `nu scripts/ocmts.nu services up ...`      | Bring up the compose stack for a cell. |
| `nu scripts/ocmts.nu services up run ...`  | Up + run Cypress headless.             |
| `nu scripts/ocmts.nu services up open ...` | Up + open Cypress UI.                  |
| `nu scripts/ocmts.nu services down ...`    | Tear down the compose stack.           |

## site

| Command                                | Purpose                                                |
| -------------------------------------- | ------------------------------------------------------ |
| `nu scripts/ocmts.nu site clone ...`   | Clone the site repo into the workspace.                |
| `nu scripts/ocmts.nu site ingest ...`  | Ingest run artifacts into the site source tree.        |
| `nu scripts/ocmts.nu site build ...`   | Build the static site.                                 |
| `nu scripts/ocmts.nu site publish ...` | Publish the built site (clone + ingest + build).       |
| `nu scripts/ocmts.nu site preview ...` | Start the local Astro preview server for a built site. |

## test

The `test` domain disambiguates between Cypress integration tests
(end-to-end, slow, Docker-driven) and internal Nushell unit tests
(fast, no Docker) via the verb path itself.

| Command                                                    | Purpose                                                                                      |
| ---------------------------------------------------------- | -------------------------------------------------------------------------------------------- |
| `nu scripts/ocmts.nu test cypress run ...`                 | Run Cypress headless against an already-up stack.                                            |
| `nu scripts/ocmts.nu test cypress suite ...`               | Run the full enabled matrix suite sequentially. Supports `--publish-site` and `--preview`.   |
| `nu scripts/ocmts.nu test units`                           | Run all internal Nushell unit suites; emits combined JSON.                                   |
| `nu scripts/ocmts.nu test units --suite <area/topic>`      | Run one unit suite (e.g. `ci/planner`).                                                      |
| `nu scripts/ocmts.nu test units --list`                    | List available unit suites.                                                                  |
| `nu scripts/ocmts.nu test units --human`                   | Run unit suites in human-friendly output mode.                                               |

## version

| Command                       | Purpose                           |
| ----------------------------- | --------------------------------- |
| `nu scripts/ocmts.nu version` | Print the OCM test suite version. |

## Notes

- Every domain is implemented in `scripts/domains/<domain>/mod.nu`. The
  top-level `scripts/ocmts.nu` only forwards arguments via `forward-to`.
- Flags after a verb are passed through unchanged because each forwarder is
  declared `def --wrapped`.
- Some verbs above abbreviate their flag set with `...`; run the verb with
  no arguments (or read its `mod.nu`) for the exact flags.
