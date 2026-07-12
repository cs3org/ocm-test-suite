# Configuration

This doc is a guide to the configuration surfaces that influence local runs and
CI runs.

## Images

`config/images.nuon` (schema v3) defines default image references, plus
optional environment-based overrides. Defaults may be scoped by `by_flow`
and `by_matrix_key`. Effective resolution uses the full tuple (`--flow`,
platforms, versions), which derives `matrix_key` and `flow_id`.

A platform is only a namespace of versions; there is no platform-root
override tier and no platform-root `default`/`override_env` fields.

Preview effective image refs for a real run:

- `nu scripts/ocmts.nu images resolve --flow ... --sender-platform ...`
  `--sender-version ...`

`images show --platform <platform> --version <version>` prints the raw
version-scoped config only (`default`, `override_env`, role env keys
when present, and any bundle slots). It does not apply `by_matrix_key`
or `by_flow` overrides; use `images resolve` with the full tuple for
the effective, override-applied refs.

### Precedence model

Precedence is scope-first: a narrower scope wins entirely before a
broader scope is even considered. Within the scope that wins, a
role-specific env override beats a shared env override, which beats
the configured default.

#### Two-party platform images

Applies to `nextcloud`, `ocis`, `opencloud`, and `ocmgo`. For a resolved
role (`sender` or `receiver`) and selected version, highest first:

1. `by_matrix_key[matrix_key].<role>_override_env`
2. `by_matrix_key[matrix_key].override_env`
3. `by_matrix_key[matrix_key].default`
4. `by_flow[flow_id].<role>_override_env`
5. `by_flow[flow_id].override_env`
6. `by_flow[flow_id].default`
7. `version.<role>_override_env`
8. `version.override_env`
9. `version.default`

#### Single-image platform main image (`cernbox` web)

`cernbox` has one main image and no sender/receiver role keys. For a
selected version, highest first:

1. `by_matrix_key[matrix_key].override_env`
2. `by_matrix_key[matrix_key].default`
3. `by_flow[flow_id].override_env`
4. `by_flow[flow_id].default`
5. `version.override_env`
6. `version.default`

#### Bundle slots (for example `cernbox/v11` `revad`, `idp`)

Bundle slots are not sender/receiver-role-based. For a selected slot,
highest first:

1. `by_matrix_key[matrix_key].override_env`
2. `by_matrix_key[matrix_key].default`
3. `by_flow[flow_id].override_env`
4. `by_flow[flow_id].default`
5. `slot.override_env`
6. `slot.default`

#### Generic leaves

Applies to `cypress.ci`, `cypress.dev`, `helpers.mariadb`,
`helpers.valkey`, `helpers.media_optimizer`, and `mitmproxy`. These
leaves are not platform-scoped and are not sender/receiver-role-based.
For a selected leaf, highest first:

1. `by_matrix_key[matrix_key].override_env`
2. `by_matrix_key[matrix_key].default`
3. `by_flow[flow_id].override_env`
4. `by_flow[flow_id].default`
5. `leaf.override_env`
6. `leaf.default`

### Env names

Two-party platform versions declare `override_env`,
`sender_override_env`, and `receiver_override_env` per version. Example
(`ocmgo/v1`):

| Scope | Env var |
| --- | --- |
| Generic (sender or receiver) | `OCMTS_OCMGO_V1_IMAGE` |
| Sender only | `OCMTS_OCMGO_V1_SENDER_IMAGE` |
| Receiver only | `OCMTS_OCMGO_V1_RECEIVER_IMAGE` |

The same pattern applies to other two-party platform versions:

- `nextcloud/v34`: `OCMTS_NEXTCLOUD_V34_IMAGE`,
  `OCMTS_NEXTCLOUD_V34_SENDER_IMAGE`,
  `OCMTS_NEXTCLOUD_V34_RECEIVER_IMAGE`
- `nextcloud/v35`: `OCMTS_NEXTCLOUD_V35_IMAGE`,
  `OCMTS_NEXTCLOUD_V35_SENDER_IMAGE`,
  `OCMTS_NEXTCLOUD_V35_RECEIVER_IMAGE`
- `opencloud/v6`: `OCMTS_OPENCLOUD_V6_IMAGE`,
  `OCMTS_OPENCLOUD_V6_SENDER_IMAGE`,
  `OCMTS_OPENCLOUD_V6_RECEIVER_IMAGE`
- `ocis/v8`: `OCMTS_OCIS_V8_IMAGE`, `OCMTS_OCIS_V8_SENDER_IMAGE`,
  `OCMTS_OCIS_V8_RECEIVER_IMAGE`

`nextcloud/v35` also declares `by_flow` overrides for two flows, each
with the same generic/sender/receiver shape:

- `contact-token`: `OCMTS_NEXTCLOUD_V35_CONTACT_TOKEN_IMAGE`,
  `OCMTS_NEXTCLOUD_V35_CONTACT_TOKEN_SENDER_IMAGE`,
  `OCMTS_NEXTCLOUD_V35_CONTACT_TOKEN_RECEIVER_IMAGE`
- `contact-wayf`: `OCMTS_NEXTCLOUD_V35_CONTACT_WAYF_IMAGE`,
  `OCMTS_NEXTCLOUD_V35_CONTACT_WAYF_SENDER_IMAGE`,
  `OCMTS_NEXTCLOUD_V35_CONTACT_WAYF_RECEIVER_IMAGE`

`cernbox/v11` declares one main image env
(`OCMTS_CERNBOX_WEB_V11_IMAGE`) with no role keys, plus bundle-slot envs
(see below).

Generic leaf env names:

| Leaf | Env var |
| --- | --- |
| `cypress.ci` | `OCMTS_CYPRESS_CI_IMAGE` |
| `cypress.dev` | `OCMTS_CYPRESS_DEV_IMAGE` |
| `helpers.mariadb` | `OCMTS_MARIADB_IMAGE` |
| `helpers.valkey` | `OCMTS_VALKEY_IMAGE` |
| `helpers.media_optimizer` | `OCMTS_MEDIA_OPTIMIZER_IMAGE` |
| `mitmproxy` | `OCMTS_MITMPROXY_IMAGE` |

Example local `ocmgo` image flow (generic override):

```bash
export OCMTS_OCMGO_V1_IMAGE=opencloudmesh-go:v1.1.0
nu scripts/ocmts.nu images show --platform ocmgo --version v1
nu scripts/ocmts.nu images resolve \
  --flow share-with \
  --sender-platform ocmgo --sender-version v1 \
  --receiver-platform nextcloud --receiver-version v34
```

Example sender-only override in a two-party run:

```bash
export OCMTS_OCMGO_V1_SENDER_IMAGE=opencloudmesh-go:v1.1.0-sender
export OCMTS_NEXTCLOUD_V34_RECEIVER_IMAGE=nextcloud:local-receiver
nu scripts/ocmts.nu images resolve \
  --flow share-with \
  --sender-platform ocmgo --sender-version v1 \
  --receiver-platform nextcloud --receiver-version v34 \
  --json
```

Overrides are temporary and shell-scoped. They are the preferred way to point
OCMTS at locally built images without changing published defaults in
`config/images.nuon`.

### Bundle slots for `cernbox/v11`

`images resolve --json` for a `cernbox` cell returns a top-level
`platform` ref (the main web image, following the six-step precedence
above) plus `bundle` and `bundle_services` maps. Bundle slots are
resolved independently of the main image and are never recomputed for
a receiver role, since `cernbox` is single-image and has no receiver
role keys.

| Image | Env var | `images resolve --json` field |
| --- | --- | --- |
| Main (web) | `OCMTS_CERNBOX_WEB_V11_IMAGE` | `platform` |

Bundle slots:

| Slot | Env var | Default compose service (`bundle_services`) |
| --- | --- | --- |
| `revad` | `OCMTS_CERNBOX_REVAD_IMAGE` | `sender-revad-gateway` |
| `idp` | `OCMTS_CERNBOX_IDP_IMAGE` | `sender-idp` |

Setting `OCMTS_CERNBOX_REVAD_IMAGE` overrides only the revad slot; other
bundle slots and the main image keep their own resolution paths.

Example cernbox bundle preview:

```bash
nu scripts/ocmts.nu images resolve \
  --flow login \
  --sender-platform cernbox --sender-version v11 \
  --json
```

### Local development loop

When developing locally and testing, you rebuild images frequently and need
ocmts to run those local images. Do not edit `config/images.nuon` for this.
Its defaults are published GHCR refs; editing them for dev churns a
published-contract file, risks committing dev refs, and pushing dev builds to
GHCR just to satisfy a default is bad practice and bandwidth-consuming.

Use shell-scoped env overrides instead. They are read live from `$env` at
resolution time (see `scripts/lib/images/precedence.nu::try-env-override`), so
they apply to every verb that resolves images: `services up run`,
`services up open`, `test cypress run`, `test cypress suite`, and
`images resolve`. No config edit is needed.

The local-build trick: build the image with the same tag as the GHCR default
carries after its registry prefix, then override the env to the local name.

```sh
docker build -t cernbox-web:master ...
export OCMTS_CERNBOX_WEB_V11_IMAGE=cernbox-web:master
```

For a one-off run, prefix the whole `nu` command with the env assignments. This
is the common local-dev loop for a cernbox -> ocis contact-token cell:

```bash
OCMTS_CERNBOX_WEB_V11_IMAGE="cernbox-web:master" \
OCMTS_CERNBOX_REVAD_IMAGE="cernbox-revad:master-development" \
OCMTS_CERNBOX_IDP_IMAGE="idp:v26.4.2" \
OCMTS_OCIS_V8_RECEIVER_IMAGE="ocis:v8.0.1" \
OCMTS_CYPRESS_CI_IMAGE="cypress:v15.14.1-ci" \
OCMTS_MITMPROXY_IMAGE="mitmproxy:v12.2.2" \
OCMTS_MARIADB_IMAGE="mariadb:11.8" \
OCMTS_VALKEY_IMAGE="valkey/valkey:9.0-alpine" \
nu scripts/ocmts.nu services up run \
  --flow contact-token \
  --sender-platform cernbox --sender-version v11 \
  --receiver-platform ocis --receiver-version v8 \
  --browser chrome --verbose
```

Use a role-specific env (`..._SENDER_IMAGE` / `..._RECEIVER_IMAGE`) when the
platform has a role in the cell (above, ocis is the receiver, so
`OCMTS_OCIS_V8_RECEIVER_IMAGE`). Use the generic env for single-image platforms
(cernbox web) and shared leaves (mariadb, valkey, mitmproxy, cypress).

For a tight edit-rebuild-test loop, `export` the overrides once and keep the
stack up between rebuilds:

```sh
export OCMTS_CERNBOX_WEB_V11_IMAGE=cernbox-web:master
# ...export the rest...
nu scripts/ocmts.nu services up run --flow login \
  --sender-platform cernbox --sender-version v11 --keep-up
# edit source, rebuild cernbox-web:master, then:
nu scripts/ocmts.nu test cypress run --flow login \
  --sender-platform cernbox --sender-version v11
nu scripts/ocmts.nu services down
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
