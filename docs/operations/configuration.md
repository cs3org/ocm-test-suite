# Configuration

This doc is a guide to the configuration surfaces that influence local runs and
CI runs.

## Images

`config/images.nuon` (schema v2) defines default image references, plus optional
environment-based overrides. Defaults may be scoped by `by_flow` and
`by_scenario`, so effective resolution depends on the scenario context, not
only platform and version.

Preview effective image refs for a real run:

- `nu scripts/ocmts.nu images resolve --scenario ...`

Note: `images show` is a raw platform/version view and does not apply
scenario-scoped overrides.

## Actors (test accounts)

Actor configuration lives under `config/actors/`:

- `config/actors/platforms/*.nuon` defines accounts for each platform
- `config/actors/scenarios/*.nuon` binds accounts to scenarios (for example
  sender/receiver for two-party flows)

`ocmts` mounts the actor config into Nextcloud and sets
`NEXTCLOUD_SEEDED_USERS_FILE` so local/CI stacks create the accounts
idempotently.

The Cypress runner receives credentials through environment injection (example
keys):

- login: `CYPRESS_nextcloud_username`, `CYPRESS_nextcloud_password`
- share-with: `CYPRESS_sender_username`, `CYPRESS_sender_password`,
  `CYPRESS_receiver_username`, `CYPRESS_receiver_password`

For manual overrides, pass the matching Cypress env keys (without the `CYPRESS_`
prefix), for example `nextcloud_username` or `sender_username`.

## Cypress environment access

This repo targets Cypress v15.10+ behavior for environment access:

- `Cypress.env()` is intentionally disabled via `allowCypressEnv: false` in
  `cypress.config.js`.
- Use `cy.env([...])` to read injected environment values in tests.
- Use `Cypress.expose(key)` for non-sensitive config that is safe to be visible
  in the browser context.

