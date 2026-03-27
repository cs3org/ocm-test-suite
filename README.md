# OCM Test Suite (reboot)

This repository is a greenfield rewrite workspace for the OCM test suite. It is
intentionally built from scratch and does not carry over legacy harness
structure or scripts.

## CLI

Run the CLI from the repository root:

- `nu scripts/ocmts.nu <domain> <verb> ...`

Root resolution:

- **Preferred**: set `OCMTS_ROOT` to this repo root
- Fallback: `git rev-parse --show-toplevel` when invoked from inside the repo

Common flows:

- `nu scripts/ocmts.nu services up run ...` brings up services, runs Cypress,
  writes `meta/run.json` and `meta/result.json`, then tears down unless
  `--keep-up` is passed.
- `nu scripts/ocmts.nu services up ...` starts the stack and leaves
  `meta/run.json` in `active` state.
- `nu scripts/ocmts.nu services up open ...` starts the dev Cypress workspace
  and leaves `meta/run.json` in `open` state until `services down`.
- `nu scripts/ocmts.nu test run ...` runs Cypress against an already-up stack
  and updates `meta/run.json` plus `meta/result.json`.
- `--record` belongs to `services up` / `services up run`; `test run` reuses
  the pre-rendered runner overlay from `services up`.

## Local artifacts

This repo writes run outputs under `./artifacts/` by default. That tree is
ignored by git.

Default layout:

- `artifacts/<artifact_name>/<execution_id>/`
  - `compose/` rendered compose inputs
  - `cypress/` screenshots, videos, downloads
  - `docker/` compose logs (when enabled)
  - `meta/` cell/run/result metadata and suite envelope outputs

## Image overrides

`config/images.nuon` defines committed default image refs, plus optional
per-run overrides via env vars. For readability, the contract direction is to
keep defaults as plain literals and resolve `override_env` in `ocmts` rather
than embedding `${ENV:-default}` expansions inside the config file.

Note: if you find an early scaffold that still embeds `${ENV:-default}` strings,
that is a transitional implementation detail, not the target contract shape.

- `OCMTS_NEXTCLOUD_IMAGE`
- `OCMTS_CYPRESS_CI_IMAGE`
- `OCMTS_CYPRESS_DEV_IMAGE`
- `OCMTS_MARIADB_IMAGE`
- `OCMTS_VALKEY_IMAGE`

## Actors

Human test accounts live under `config/actors/`:

- `config/actors/platforms/nextcloud.nuon` defines person-shaped Nextcloud
  accounts such as `michiel` and `marie`.
- `config/actors/scenarios/login.nuon` selects which account the login
  scenario uses.

`ocmts` mounts the actor config into Nextcloud and sets
`NEXTCLOUD_SEEDED_USERS_FILE` so local/CI stacks create the accounts
idempotently. The Cypress runner receives the selected credentials through
`CYPRESS_nextcloud_username` and `CYPRESS_nextcloud_password`.

For manual overrides, keep using `nextcloud_username` and
`nextcloud_password` in Cypress env.

## Slice 1

The first proof slice is `login__nextcloud-v33` and runs without MITM.
