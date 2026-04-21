# OCM Test Suite

This repository is a greenfield rewrite workspace for the OCM test suite. It is
intentionally built from scratch and does not carry over legacy harness
structure or scripts.

Legacy policy:

- Legacy-first, clean rewrite is mandatory. Inspect the analogous legacy Cypress
spec and helpers first to learn stable sequence and selectors, then rewrite
into the new TypeScript contracts.
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
- `nu scripts/ocmts.nu test cypress run ...` runs Cypress against an
already-up stack and updates `meta/run.json` plus `meta/result.json`.
- `nu scripts/ocmts.nu test cypress suite ...` runs the full enabled matrix
suite sequentially. Add `--publish-site` to publish the exact suite that just
ran. Add `--site-dir <path>` with `--publish-site` to target an existing local
`ocm-web-site` worktree without cloning or fetching it. Add `--preview` (with
`--publish-site`) to start the Astro preview server after publish.
- `nu scripts/ocmts.nu test units` runs the internal Nushell unit-test suite
for the `ocmts` CLI library code. This is distinct from the Cypress E2E suite
above and runs in seconds with no Docker. Use `--suite <area/topic>` to scope
to one suite, `--list` to discover suites, `--human` for human-readable
output.
- Video recording is enabled by default. To opt out, pass `--no-video` to
`services up`, `services up run`, or `services up open`. `test cypress run`
reuses the pre-rendered runner overlay from `services up` / `services up
open`, so the video setting is inherited.
- Local `test cypress suite --publish-site` publishes observed suite state.
It does not inject CI-style synthetic `missing` results for planned cells
that never ran.
- When `--site-dir` is omitted with `--publish-site`, the site directory is
auto-resolved from `OCM_WEB_SITE_DIR` (env), then `<repo>/../ocm-web-site`
(if present), then cloned by the publish path.

## Flow identity

This repo treats flow identity as explicit data.

- `--scenario` selects the scenario module key (for example `login`).
- Each scenario has an explicit public `flow_id` in `config/matrix-rules.nuon`.
- Today public flow ids in this repo match scenario module names:
  - `login`
  - `share-with`
  - `contact-token`
  - `contact-wayf`
  - `code-flow`
- `cell_id` and `artifact_name` use `flow_id` as the leading segment.
- `meta/cell.json` includes both `flow_id` and `scenario_module`.

Legacy naming note:

- Legacy names such as `invite-link` and standalone `wayf` are comparison-only
terms for the old suite. This suite must not emit them as `flow_id` values.

Contact flows:

- `contact-token` is a full UI E2E flow: invite, accept contact, prove contact,
create and save a file, share with the established contact, and prove receiver
visibility.
- Reva-based contact-token cells use distinct sender and receiver demo users.
See `docs/testing/contact-token-platforms.md` for the actor and provider JSON
contract.
- `contact-wayf` stays scoped to platforms that expose a WAYF UI.
- `code-flow` remains placeholder-only.

## Local artifacts

This repo writes run outputs under `./artifacts/` by default. That tree is
ignored by git.

Default layout:

- `artifacts/<flow_id>/<pair>/<execution_id>/`
  - `compose/` rendered compose inputs
  - `cypress/` screenshots, videos, downloads
    - `videos/*.mp4` (when video is enabled)
    - `screenshots/**/*.png` on failure, plus explicit proof screenshots from
    the shared Cypress evidence helper
  - `docker/logs/` docker compose logs and runner output
    - `cypress-run.log` stdout+stderr from `docker compose run --rm cypress`
    (captured by both `services up run` and `test cypress run`).
    - `platform.log`, `platform-db.log`, `platform-cache.log` collected by
    `services up run` before teardown, or by
    `nu scripts/ocmts.nu artifacts collect --include-logs ...` while the
    stack is still up.
  - `meta/` cell/run/result metadata and suite envelope outputs
- `artifacts/<flow_id>/<pair>/LAST_EXECUTION_ID` marker written at run setup
- `artifacts/suites/LATEST_SUITE_ID` latest suite marker
- `artifacts/suites/runs/<suite_id>.json` suite records (schema v2)

Where `pair` is role-ordered and opaque:

- 1-party: `<sender_platform>-<sender_version>`
(example: `nextcloud-v33`)
- 2-party: `<sender_platform>-<sender_version>-<receiver_platform>-<receiver_version>`
(example: `nextcloud-v33-nextcloud-v33`)

Evidence policy and site publication details live in:

- `docs/architecture/evidence-standard.md`
- `docs/testing/cypress-evidence.md`
- `docs/operations/site-publish.md`

## Image overrides

`config/images.nuon` uses schema v2. It defines committed default image refs,
plus optional env-based overrides. Image defaults may be scoped by
`by_flow` and `by_scenario`, so effective resolution depends on the scenario
context, not only platform and version.

Use `nu scripts/ocmts.nu images resolve --scenario ...` to preview the
effective image refs for a real run. `images show` is a raw platform/version
config view and does not apply scenario-scoped overrides.

Current Nextcloud v34 policy:

- Generic v34 flows such as `login` and `share-with` use `nextcloud:master`.
- Contact flows override v34 to `nextcloud-contacts:sta-ocm-m6`.

For readability, defaults stay as plain literals and `ocmts` resolves
`override_env` keys at runtime instead of embedding `${ENV:-default}`
expansions inside the config file.

Toolchain source of truth:

- The Cypress image (built and published from `repos/containers`) is the runtime
toolchain source of truth.
- `package.json` here is allowed to exist as host editor and tooling metadata.
- This repo does not require a lockfile solely because `package.json` exists.
- `OCMTS_NEXTCLOUD_IMAGE`
- `OCMTS_OCIS_IMAGE`
- `OCMTS_OPENCLOUD_IMAGE`
- `OCMTS_CYPRESS_CI_IMAGE`
- `OCMTS_CYPRESS_DEV_IMAGE`
- `OCMTS_MARIADB_IMAGE`
- `OCMTS_VALKEY_IMAGE`
- `OCMTS_MITMPROXY_IMAGE`

## Actors

Human test accounts live under `config/actors/`:

- `config/actors/platforms/nextcloud.nuon` defines person-shaped Nextcloud
accounts such as `michiel` and `marie`.
- `config/actors/platforms/ocis.nuon` and
`config/actors/platforms/opencloud.nuon` define demo users supplied by the
platform images.
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

`contact-token` uses the same sender/receiver env keys as `share-with`, but
the actors are flow-specific. Same-platform oCIS/OpenCloud contact-token cells
intentionally use two different demo users so screenshots and contact/share
assertions show two people, not one account on two hosts.

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

## Cypress matrix selection

`ocmts` dev mode injects `CYPRESS_proof_cell` and Cypress spec entrypoints
require it. In Cypress/VNC, select the flow spec (`login`, `share-with`,
`contact-token`, or `contact-wayf`), not a platform/version combination.

Direct host Cypress without `CYPRESS_proof_cell` is not a supported path.
Use `nu scripts/ocmts.nu services up run`, `services up open`, or
`test cypress run` so `ocmts` selects one generated matrix cell for the spec.

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

Reason: Tests in this suite should avoid Cypress cross-origin mode and its
restrictions.
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
