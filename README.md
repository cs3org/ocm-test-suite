# OCM Test Suite

End-to-end tests for Open Cloud Mesh (OCM) interoperability across multiple
providers (for example Nextcloud, oCIS, OpenCloud). The suite runs real UI
flows, captures evidence (screenshots, videos, logs, metadata), and can publish
results to a static site.

If you are here to run the suite, start with "Quick start". If you are here to
understand how it is built, use the docs index under `docs/`.

## Quick start

Prereqs:

- Nushell (`nu`)
- Docker (and Docker Compose)

Get help and discover commands:

- `nu scripts/ocmts.nu`
- `nu scripts/ocmts.nu services up run --help`
- `nu scripts/ocmts.nu test cypress suite --help`

Run a single cell locally (brings up services, runs Cypress, collects
artifacts, then tears down unless `--keep-up` is used):

- `nu scripts/ocmts.nu services up run ...`

Run the full enabled suite locally:

- `nu scripts/ocmts.nu test cypress suite ...`

Run fast internal unit tests (no Docker):

- `nu scripts/ocmts.nu test units`

## Where to read next

- **Docs index**: `docs/README.md`
- **CLI and local run details**: `docs/operations/cli.md`
- **Configuration (images, actors, Cypress env)**: `docs/operations/configuration.md`
- **Flow identity (flow_id vs scenario key)**: `docs/architecture/scenario-keys.md`
- **Evidence and publication**: `docs/architecture/evidence-standard.md`,
  `docs/operations/site-publish.md`
- **Automation layout**: `scripts/README.md`
- **CI workflow generation**: `config/ci/README.md`
