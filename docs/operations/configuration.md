# Configuration

This doc is a guide to the configuration surfaces that influence local runs and
CI runs.

## Images

`config/images.nuon` (schema v2) defines default image references, plus
optional environment-based overrides. Defaults may be scoped by `by_flow` and
`by_matrix_key`. Effective resolution uses the full tuple (`--flow`, platforms,
versions), which derives `matrix_key` and `flow_id`.

Preview effective image refs for a real run:

- `nu scripts/ocmts.nu images resolve --flow ... --sender-platform ...`
  `--sender-version ...`

Note: `images show` is a raw platform/version view. It does not apply `by_flow`
or `by_matrix_key` overrides; use `images resolve` with the full tuple for
effective refs.

### Image overrides

Platform image refs can be overridden through `config/images.nuon` env keys.
Each platform may declare up to three platform-level keys:

- `override_env` -- generic override for either sender or receiver role
- `sender_override_env` -- narrower override when the platform is the sender
- `receiver_override_env` -- narrower override when the platform is the receiver

Role-specific keys win over the generic key for that role. When a role-specific
key is unset or empty in the shell, resolution falls back through the generic
`override_env` chain and then to configured defaults.

Precedence for a platform version and role (sender or receiver), highest
first:

1. `by_matrix_key[matrix_key].<role>_override_env` (env lookup)
2. `by_flow[flow_id].<role>_override_env` (env lookup)
3. version `<role>_override_env` (env lookup)
4. platform `<role>_override_env` (env lookup)
5. `by_matrix_key[matrix_key].override_env` (env lookup)
6. `by_flow[flow_id].override_env` (env lookup)
7. version `override_env` (env lookup)
8. platform `override_env` (env lookup)
9. `by_matrix_key[matrix_key].default`
10. `by_flow[flow_id].default`
11. version `default`

`images resolve` applies this chain with the full run tuple (`--flow`,
platforms, versions). `images show` prints generic `override_env` keys for a
platform/version pair only; it does not list role-specific env names and does
not apply `by_flow`, `by_matrix_key`, or role context. Use this doc and
`config/images.nuon` for the full override surface.

#### Generic and role-specific env names

For a two-party platform (example: `ocmgo`):

| Scope | Env var |
| --- | --- |
| Generic (sender or receiver) | `OCMTS_OCMGO_IMAGE` |
| Sender only | `OCMTS_OCMGO_SENDER_IMAGE` |
| Receiver only | `OCMTS_OCMGO_RECEIVER_IMAGE` |

The same pattern applies to other two-party platforms:

- `nextcloud`: `OCMTS_NEXTCLOUD_IMAGE`, `OCMTS_NEXTCLOUD_SENDER_IMAGE`,
  `OCMTS_NEXTCLOUD_RECEIVER_IMAGE`
- `opencloud`: `OCMTS_OPENCLOUD_IMAGE`, `OCMTS_OPENCLOUD_SENDER_IMAGE`,
  `OCMTS_OPENCLOUD_RECEIVER_IMAGE`
- `ocis`: `OCMTS_OCIS_IMAGE`, `OCMTS_OCIS_SENDER_IMAGE`,
  `OCMTS_OCIS_RECEIVER_IMAGE`

`cernbox` keeps a single platform web image override
(`OCMTS_CERNBOX_WEB_IMAGE`) plus per-slot bundle overrides (see below). It
does not declare platform-level sender/receiver env names because the web
image name already encodes the primary container role.

Example local `ocmgo` image flow (generic override):

```bash
export OCMTS_OCMGO_IMAGE=opencloudmesh-go:local
nu scripts/ocmts.nu images show --platform ocmgo --version v1
nu scripts/ocmts.nu images resolve \
  --flow share-with \
  --sender-platform ocmgo --sender-version v1 \
  --receiver-platform nextcloud --receiver-version v34
```

Example sender-only override in a two-party run:

```bash
export OCMTS_OCMGO_SENDER_IMAGE=opencloudmesh-go:local-sender
export OCMTS_NEXTCLOUD_RECEIVER_IMAGE=nextcloud:local-receiver
nu scripts/ocmts.nu images resolve \
  --flow share-with \
  --sender-platform ocmgo --sender-version v1 \
  --receiver-platform nextcloud --receiver-version v34 \
  --json
```

Overrides are temporary and shell-scoped. They are the preferred way to point
OCMTS at locally built images without changing published defaults in
`config/images.nuon`.

#### Bundle slot overrides

Some platform versions declare a `bundle` map (today: `cernbox/v11`). For
those runs, `images resolve --json` returns a top-level `platform` ref plus
`bundle` and `bundle_services` maps. The `platform` value is the sender
platform image (for cernbox, the web container). It follows the 11-step
role-aware precedence above. Receiver resolution uses only the receiver
platform image ref; bundle slots are not recomputed for the receiver role.

Bundle service slots (`revad`, `idp`, ...) are non-platform leaves. Each slot
uses this six-step precedence (highest first):

1. `by_matrix_key[matrix_key].override_env` (env lookup)
2. `by_flow[flow_id].override_env` (env lookup)
3. slot `override_env` (env lookup)
4. `by_matrix_key[matrix_key].default`
5. `by_flow[flow_id].default`
6. slot `default`

Bundle slot precedence is separate from role precedence: slots do not use
sender/receiver env names. Setting `OCMTS_CERNBOX_REVAD_IMAGE` overrides only
the revad slot; other bundle slots and the sender platform image keep their
own resolution paths.

For `cernbox/v11`, the sender platform image is separate from bundle slots:

| Image | Env var | `images resolve --json` field |
| --- | --- | --- |
| Sender platform (web) | `OCMTS_CERNBOX_WEB_IMAGE` | `platform` |

Bundle slots for `cernbox/v11`:

| Slot | Env var | Default compose service (`bundle_services`) |
| --- | --- | --- |
| `revad` | `OCMTS_CERNBOX_REVAD_IMAGE` | `sender-revad-gateway` |
| `idp` | `OCMTS_CERNBOX_IDP_IMAGE` | `sender-idp` |

Example cernbox bundle preview:

```bash
nu scripts/ocmts.nu images resolve \
  --flow login \
  --sender-platform cernbox --sender-version v11 \
  --json
```

## Actors (test accounts)

Actor configuration lives under `config/actors/`:

- `config/actors/platforms/*.nuon` defines accounts for each platform
- `config/actors/overrides/*.nuon` binds accounts to matrix cells

Override filenames use the tuple `matrix_key` (for example
`login__nextcloud` or `share-with__nextcloud__ocmgo`). Tuple-based actor
commands require `--flow` and
`--sender-platform`; two-party flows also require `--receiver-platform`.

Examples:

```bash
nu scripts/ocmts.nu actors show --flow login --sender-platform nextcloud
nu scripts/ocmts.nu actors validate \
  --flow share-with \
  --sender-platform nextcloud \
  --receiver-platform ocmgo
```

An override file must contain at least one non-empty `platform` or
`account` value in `actor`, `sender`, or `receiver`. Empty files and
empty-string-only role blocks (for example `{actor: {account: ""}}`) are
rejected with a clear error.

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

For MITM-backed two-party matrix cells, OCMTS writes the platform proxy
contract into `compose/inputs/stack.env` before Docker starts. Review
these files in order when debugging outbound traffic routing:

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
