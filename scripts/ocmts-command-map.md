# ocmts command map

<!-- markdownlint-disable MD013 -->

Flat reference of every `nu scripts/ocmts.nu <domain> <verb>` form,
generated from `scripts/domains/*/mod.nu`. Run `nu scripts/ocmts.nu
<domain>` for the live per-domain help, which is always authoritative.

Run from the repo root.

## actors

| Command                                              | Purpose                                                           |
| ---------------------------------------------------- | ----------------------------------------------------------------- |
| `nu scripts/ocmts.nu actors list`                    | List matrix keys enabled in the matrix SSOT.                      |
| `nu scripts/ocmts.nu actors list overrides`          | List matrix keys with override files in `config/actors/overrides/`. |
| `nu scripts/ocmts.nu actors show --flow ...`         | Show resolved actor record for a tuple.                           |
| `nu scripts/ocmts.nu actors validate --flow ...`   | Validate one tuple's resolution.                                  |
| `nu scripts/ocmts.nu actors validate-all`            | Validate every matrix-enabled tuple.                              |

## artifacts

| Command | Purpose |
| --- | --- |
| `nu scripts/ocmts.nu artifacts list` | List artifact directories on disk. |
| `nu scripts/ocmts.nu artifacts show <run>` | Show one run's artifact tree summary. |
| `nu scripts/ocmts.nu artifacts collect ...` | Collect post-run artifacts for one cell. |
| `nu scripts/ocmts.nu artifacts publish ...` | Publish/copy artifacts to the publish target. |
| `nu scripts/ocmts.nu artifacts prune ...` | Prune old artifact directories. |
| `nu scripts/ocmts.nu artifacts optimize-media ...` | Optimize raw cell media (images/video) into a smaller form. |
| `nu scripts/ocmts.nu artifacts show-optimizer-image` | Print the resolved media optimizer image ref. |
| `nu scripts/ocmts.nu artifacts probe-optimizer` | Probe the media optimizer image (pull/verify availability). |
| `nu scripts/ocmts.nu artifacts aggregate-optimized-media ...` | Aggregate per-cell optimized media dirs into one summary. |

## ci

| Command | Purpose |
| --- | --- |
| `nu scripts/ocmts.nu ci suite-id [--override <id>]` | Print a suite ID or pass through an explicit override. |
| `nu scripts/ocmts.nu ci exec-id` | Print a new unique execution ID. |
| `nu scripts/ocmts.nu ci plan ...` | Plan a suite (cells, order, exec ids). |
| `nu scripts/ocmts.nu ci workflows generate github` | Render GitHub workflow YAMLs from blueprints. |
| `nu scripts/ocmts.nu ci workflows check github` | Drift-check rendered workflows against blueprints. |
| `nu scripts/ocmts.nu ci aggregate ...` | Aggregate per-cell suite manifests into one. |
| `nu scripts/ocmts.nu ci emit-blocked ...` | Emit a blocked-cell artifact set. |
| `nu scripts/ocmts.nu ci check-prereq-status ...` | Check prerequisite artifacts and print the first failure reason. |
| `nu scripts/ocmts.nu ci read-cells-json <path>` | Read a cells JSON asset file and print compact one-line JSON. |
| `nu scripts/ocmts.nu ci find-suite-dirs <root>` | Find suite execution dirs under a root for aggregate `--dirs-file`. |
| `nu scripts/ocmts.nu ci resolve-source-run ...` | Resolve a source run ID from an explicit input or GitHub lookup. |
| `nu scripts/ocmts.nu ci download-prereqs ...` | Download prerequisite artifacts into `prereqs/<dep>` dirs. |

## images

| Command                                    | Purpose                              |
| ------------------------------------------ | ------------------------------------ |
| `nu scripts/ocmts.nu images list [--json]` | List configured images.              |
| `nu scripts/ocmts.nu images show <id>`     | Show one image's resolved config.    |
| `nu scripts/ocmts.nu images resolve ...`   | Resolve image precedence for a cell. |

## matrix

| Command                                                    | Purpose                                                                                           |
| ---------------------------------------------------------- | ------------------------------------------------------------------------------------------------- |
| `nu scripts/ocmts.nu matrix gen cypress`                   | Regenerate `cypress/e2e/<flow>/matrix.ts` files.                                                  |
| `nu scripts/ocmts.nu matrix list [--json]`                 | List expanded matrix cells (version pairs x browsers).                                            |
| `nu scripts/ocmts.nu matrix list entries [--json] [--md]`  | List matrix rules entries (one row per `matrix_key`); `--json` and `--md` are mutually exclusive. |
| `nu scripts/ocmts.nu matrix cell ...`                      | Show one cell record.                                                                             |
| `nu scripts/ocmts.nu matrix check capabilities`            | Validate adapter capabilities SSOT against platforms, flows, registry, and public-site files.     |

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

| Command                                                               | Purpose                                                                                   |
| --------------------------------------------------------------------- | ----------------------------------------------------------------------------------------- |
| `nu scripts/ocmts.nu test cypress run ...`                            | Run Cypress headless against an already-up stack.                                         |
| `nu scripts/ocmts.nu test cypress suite ...`                          | Run the full enabled matrix suite sequentially. Supports `--publish-site` and `--preview`.|
| `nu scripts/ocmts.nu test units`                                      | Run all non-manual unit suites; emits combined JSON.                                      |
| `nu scripts/ocmts.nu test units --suite <area/topic>`                 | Run one unit suite (e.g. `ci/planner`).                                                   |
| `nu scripts/ocmts.nu test units --suite <area/topic> --include-manual`| Run one manual unit suite.                                                                |
| `nu scripts/ocmts.nu test units --suites <a,b,c>`                     | Run multiple unit suites by comma-separated IDs.                                          |
| `nu scripts/ocmts.nu test units --list`                               | List non-manual unit suites.                                                              |
| `nu scripts/ocmts.nu test units --list --include-manual`              | List all unit suites including manual.                                                    |
| `nu scripts/ocmts.nu test units --human`                              | Human-friendly output; applies to all run modes.                                          |

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
