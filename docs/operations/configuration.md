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

### Image overrides

Platform image refs can be overridden through `config/images.nuon`
`override_env` keys.

For `ocmgo/v1`, the operator override is:

- `OCMTS_OCMGO_IMAGE`

Example local `ocmgo` image flow:

```bash
export OCMTS_OCMGO_IMAGE=opencloudmesh-go:local
nu scripts/ocmts.nu images show --platform ocmgo --version v1
nu scripts/ocmts.nu images resolve \
  --scenario share-with-ocmgo-nc \
  --sender-platform ocmgo --sender-version v1 \
  --receiver-platform nextcloud --receiver-version v34
```

This override is temporary and shell-scoped. It is the preferred way to point
OCMTS at a locally built `ocmgo` image without changing the published image
defaults.

For `ocmgo` sender/receiver pairs, the same override applies to both roles
unless a narrower role-specific override is added in `config/images.nuon`.

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

## Execution subnet and ocmgo route envs

Every run derives a deterministic execution subnet from `execution_id`.
OCMTS maps the first two hex byte pairs in the `execution_id` suffix to
`10.<B>.<C>.0/24`, then writes that `exec_cidr` into
`compose/inputs/exec.yml` as the `ocm-net` subnet.

Two-party runs reuse that same `exec_cidr` when a role platform is
`ocmgo`. `compose/inputs/stack.env` sets
`OCM_GO_<ROLE>_ROUTE_SUFFIXES=.docker` and
`OCM_GO_<ROLE>_ROUTE_PRIVATE_CIDRS=<exec_cidr>` for each `ocmgo`
sender or receiver. One-party runs, and any role whose platform is not
`ocmgo`, still emit those keys but leave them blank.

Before Docker Compose starts, OCMTS runs subnet preflight against the
derived `exec_cidr`. Malformed CIDRs and overlaps with active Docker
network subnets fail early with a clear error that names the rejected
`exec_cidr` and the conflicting Docker networks.

When debugging route or subnet issues, inspect these in order:

- `compose/inputs/exec.yml` for the resolved `ocm-net` subnet.
- `compose/inputs/stack.env` for the `OCM_GO_<ROLE>_ROUTE_SUFFIXES` and
  `OCM_GO_<ROLE>_ROUTE_PRIVATE_CIDRS` values that were handed to Docker
  Compose.
- If setup fails before `compose/inputs/` exists, use the CLI error as
  the source of truth for the rejected `exec_cidr` and any overlapping
  active Docker network subnets.

## MITM and proxy evidence

Two-party MITM scenarios write the platform proxy contract into
`compose/inputs/stack.env` before Docker starts. Review these files in order
when debugging outbound traffic routing:

- `compose/inputs/stack.env`
- `mitm/startup.v1.json`
- `mitm/peers.json`
- `mitm/flows/traffic.jsonl`
- `mitm/reports/*`

For share-with flows, `stack.env` is the first place to confirm
`SENDER_HTTP_PROXY`, `SENDER_HTTPS_PROXY`, `RECEIVER_HTTP_PROXY`, and
`RECEIVER_HTTPS_PROXY` point at `http://mitm:8080`.

## Cypress environment access

This repo targets Cypress v15.10+ behavior for environment access:

- `Cypress.env()` is intentionally disabled via `allowCypressEnv: false` in
  `cypress.config.js`.
- Use `cy.env([...])` to read injected environment values in tests.
- Use `Cypress.expose(key)` for non-sensitive config that is safe to be visible
  in the browser context.

