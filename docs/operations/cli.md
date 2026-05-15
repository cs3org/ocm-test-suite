# CLI and local runs

The `ocmts` CLI is the main entry point for running the suite locally and in
CI.

Run the CLI from the repository root:

- `nu scripts/ocmts.nu <domain> <verb> ...`

Repo root resolution:

- Preferred: set `OCMTS_ROOT` to this repo root
- Fallback: `git rev-parse --show-toplevel` when invoked from inside the repo

Common flows:

- `nu scripts/ocmts.nu services up run ...` brings up services, runs Cypress,
  writes `meta/run.json` and `meta/result.v1.json` (plus per-cell sidecars),
  then tears down unless `--keep-up` is passed.
- `nu scripts/ocmts.nu services up ...` starts the stack and leaves `meta/run.json`
  in `active` state.
- `nu scripts/ocmts.nu services up open ...` starts the dev Cypress workspace and
  leaves `meta/run.json` in `open` state until `services down`.
- `nu scripts/ocmts.nu test cypress run ...` runs Cypress against an already-up
  stack and updates `meta/run.json` plus `meta/result.v1.json`.
- `nu scripts/ocmts.nu test cypress suite ...` runs the full enabled matrix suite
  sequentially. Add `--publish-site` to publish the exact suite that just ran.
- `nu scripts/ocmts.nu test units` runs the internal Nushell unit-test suite for
  the `ocmts` CLI library code. This runs in seconds and does not require Docker.

Video recording:

- Video recording is enabled by default.
- To opt out, pass `--no-video` to `services up`, `services up run`, or `services up open`.

Site publish (local):

- `nu scripts/ocmts.nu test cypress suite --publish-site ...` publishes observed suite state.
  It does not inject CI-style synthetic `missing` results for planned cells that never ran.
- When `--site-dir` is omitted with `--publish-site`, the site directory is auto-resolved
  from `OCM_WEB_SITE_DIR` (env), then `<repo>/../ocm-web-site` (if present), then cloned by
  the publish path.

