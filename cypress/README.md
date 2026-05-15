# cypress/ - End-to-end integration tests

This directory holds the Cypress end-to-end specs that exercise OCM
flows against real platform stacks (Nextcloud, oCIS, OpenCloud) running
in Docker.

## Invoke via the ocmts CLI

Always invoke Cypress through the `ocmts` CLI so service stacks,
artifact directories, matrix selection, and credentials are wired
correctly.

```sh
nu scripts/ocmts.nu test cypress run ...     # one matrix cell against an already-up stack
nu scripts/ocmts.nu test cypress suite ...   # full enabled matrix sequentially
nu scripts/ocmts.nu services up run ...      # one cell start-to-finish (up + run + down)
```

Direct host Cypress without `ocmts` is not a supported path; specs
require the injected `CYPRESS_proof_cell` env value that `ocmts`
provides.

## Not the same as the Nushell unit tests

The internal Nushell unit tests for the `ocmts` CLI library live under
`scripts/tests/<area>/<topic>.nu` and are invoked via
`nu scripts/ocmts.nu test units`. They are fast, run without Docker,
and exercise pure-Nushell library code under `scripts/lib/`. They have
nothing to do with the Cypress specs in this directory.

## Layout

- `e2e/<flow>/` per-flow Cypress specs (login, share-with,
  contact-token, contact-wayf, code-flow).
- `support/` shared helpers (commands, evidence, env access).
- `cypress.config.js` Cypress configuration with the strict policies
  documented in the repo root `README.md` (no `cy.origin`,
  `allowCypressEnv: false`, etc.).
