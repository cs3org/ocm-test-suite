# OCM Test Suite (reboot)

This repository is a greenfield rewrite workspace for the OCM test suite. It is
intentionally built from scratch and does not carry over legacy harness
structure or scripts.

Legacy policy:

- Legacy-first, clean rewrite is mandatory. Inspect the analogous legacy Cypress
  spec and helpers first to learn stable sequence and selectors, then rewrite
  into the reboot TypeScript contracts.
- Legacy is reference material, not a code template. Do not copy the legacy
  JavaScript layout or helper-bag architecture.

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
- Video recording is enabled by default. To opt out, pass `--no-video` to
  `services up`, `services up run`, or `services up open`. `test run` reuses the
  pre-rendered runner overlay from `services up` / `services up open`, so the
  video setting is inherited.

## Local artifacts

This repo writes run outputs under `./artifacts/` by default. That tree is
ignored by git.

Default layout:

- `artifacts/<artifact_name>/<execution_id>/`
  - `compose/` rendered compose inputs
  - `cypress/` screenshots, videos, downloads
    - `videos/*.mp4` (when video is enabled)
    - `screenshots/*.png` on failure, plus any explicit `cy.screenshot(...)`
      calls in tests (for example share-with takes on-success screenshots)
  - `docker/logs/` docker compose logs and runner output
    - `cypress-run.log` stdout+stderr from `docker compose run --rm cypress`
      (captured by both `services up run` and `test run`).
    - `platform.log`, `platform-db.log`, `platform-cache.log` collected by
      `services up run` before teardown, or by
      `nu scripts/ocmts.nu artifacts collect --include-logs ...` while the stack
      is still up.
  - `meta/` cell/run/result metadata and suite envelope outputs

## Image overrides

`config/images.nuon` defines committed default image refs, plus optional
per-run overrides via env vars. For readability, the contract direction is to
keep defaults as plain literals and resolve `override_env` in `ocmts` rather
than embedding `${ENV:-default}` expansions inside the config file.

Note: if you find an early scaffold that still embeds `${ENV:-default}` strings,
that is a transitional implementation detail, not the target contract shape.

Toolchain source of truth:

- The Cypress image (built and published from `repos/containers`) is the runtime
  toolchain source of truth.
- `package.json` here is allowed to exist as host editor and tooling metadata.
- This repo does not require a lockfile solely because `package.json` exists.

- `OCMTS_NEXTCLOUD_IMAGE`
- `OCMTS_CYPRESS_CI_IMAGE`
- `OCMTS_CYPRESS_DEV_IMAGE`
- `OCMTS_MARIADB_IMAGE`
- `OCMTS_VALKEY_IMAGE`
- `OCMTS_MITMPROXY_IMAGE`

## Actors

Human test accounts live under `config/actors/`:

- `config/actors/platforms/nextcloud.nuon` defines person-shaped Nextcloud
  accounts such as `michiel` and `marie`.
- `config/actors/scenarios/login.nuon` selects which account the login
  scenario uses.
- `config/actors/scenarios/share-with.nuon` binds sender and receiver accounts
  for the two-party share-with scenario.

`ocmts` mounts the actor config into Nextcloud and sets
`NEXTCLOUD_SEEDED_USERS_FILE` so local/CI stacks create the accounts
idempotently. The Cypress runner receives the selected credentials through
environment injection:

- login: `CYPRESS_nextcloud_username`, `CYPRESS_nextcloud_password`
- share-with: `CYPRESS_sender_username`, `CYPRESS_sender_password`,
  `CYPRESS_receiver_username`, `CYPRESS_receiver_password`

For manual overrides, pass the matching Cypress env keys (without the
`CYPRESS_` prefix), for example `nextcloud_username` or `sender_username`.

## Cypress v15 env access: cy.env and Cypress.expose

This repo targets Cypress v15.10+ behavior for environment access.

- `Cypress.env()` is intentionally disabled via `allowCypressEnv: false` in
  `cypress.config.js`.
- Use `cy.env([...])` to read injected environment values in tests. This is the
  supported API for sensitive values such as credentials. The command is async
  and yields a key -> value record.
- Use `Cypress.expose(key)` for non-sensitive config that is safe to be visible
  in the browser context. Values come from the `expose` map in
  `cypress.config.js` (for example `receiver_baseUrl` is injected as
  `CYPRESS_receiver_baseUrl` and read via `Cypress.expose("receiver_baseUrl")`).

## Slice 1

The first scenario is `login__nextcloud-v33` and runs without MITM.
There are no MITM logs for the login scenario.

## Slice 2

The next scenario is `share-with__nextcloud-v33__nextcloud-v33` and is
MITM-backed by default. It runs a two-party topology (sender + receiver) and
adds a `mitm/` artifact subtree, plus MITM service logs.

MITM flow artifacts:

- `mitm/flows/traffic.jsonl` is written by the mitm service during the run.
- `mitm/flows/session.json` is written at mitm shutdown.
- Derived reports are generated at the end of `services up run` (two-party only)
  under `mitm/reports/`:
  - `01-01-traffic-overview.md`
  - `01-02-traffic-overview.json`
  - `02-01-ocm-endpoints.md`
  - `02-02-ocm-endpoints.json`
  - `03-01-ocm-details.md`
  - `03-02-ocm-details.json`
  - `03-03-ocm-details.tsv`
  - `99-traffic-pretty.json`

MITM evidence policy:

- MITM output is test and development evidence.
- Default policy is no redaction: preserve useful protocol and debug detail as
  captured.
- Do not describe this like production secret handling.

## Cypress policy: no cy.origin

Do not use `cy.origin()` in this repo.

Reason: OTS tests should avoid Cypress cross-origin mode and its restrictions.
Multi-party OCM flows are represented as ordered scenario phases:

- Keep sender and receiver work in separate ordered `it` blocks unless a future
  explicit, flow-specific exception is approved.
- CI must not shard within a spec at the individual `it` level, because those
  ordered phases share server-side state.
- Legacy `share-with` follows this pattern with two ordered `it` blocks: sender
  shares, then receiver accepts.

Enforcement: `cypress/support/e2e.ts` overwrites the `origin` command to throw.

Exception policy:

- `cy.origin()` stays forbidden by default.
- Any exception must be explicit and flow-specific.
- The only known legacy `cy.origin()` use is a deprecated ownCloud group flow
  and must not be treated as a general pattern.
