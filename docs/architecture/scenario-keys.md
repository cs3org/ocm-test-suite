# Tuple Identity (flow + platforms)

This file keeps the historical filename `scenario-keys.md`, but the content
documents tuple identity: `flow_id`, `matrix_key`, and `cell_id`.

OCMTS identifies a matrix cell with an explicit tuple, not a derived
scenario slug. Operator CLIs take `--flow`, `--sender-platform`,
`--sender-version`, and (for two-party flows) `--receiver-platform` and
`--receiver-version`. Internal lookups use a version-less `matrix_key`.

## Vocabulary

| Term           | Definition                                                                 |
| -------------- | -------------------------------------------------------------------------- |
| `flow_id`      | Public flow name (`login`, `share-with`, `contact-token`, `contact-wayf`). Stable across versions and pairs. |
| `matrix_key`   | Version-less internal lookup key. Shape `<flow_id>__<sender_platform>[__<receiver_platform>]`. Platform names, not slugs. |
| `cell_id`      | Per-pair, per-version artifact id. Shape `<flow_id>__<sender_platform>-<sender_version>[__<receiver_platform>-<receiver_version>]`. |
| `pair`         | Role-ordered artifact path segment. One-party: `<sender_platform>-<sender_version>`. Two-party: `<sender>-<sver>-<recv>-<rver>`. |
| `scenario_module` | Cypress module directory name under `cypress/e2e/`. Equals `flow_id` today. |

The tuple is what operators pass on the CLI. `matrix_key` is what matrix
rules, actor overrides, and image override resolution use internally.
`cell_id` is what artifact directories and the published matrix UI show.

## matrix_key convention

Defined in `scripts/lib/matrix/rules-gen.nu::matrix-key`.

Inputs:

- `flow_id`
- `sender_platform` (e.g. `nextcloud`, `ocis`, `opencloud`, `ocmgo`)
- `receiver_platform`, or empty for one-party flows

Rules:

1. One-party: `<flow_id>__<sender_platform>` (example: `login__ocis`).
2. Two-party: `<flow_id>__<sender_platform>__<receiver_platform>`
   (example: `share-with__nextcloud__ocmgo`).

There is no baseline aliasing, slug shortening, or `naming.nuon`
remapping. Every enabled (flow, sender, receiver) pair has exactly one
`matrix_key`.

## Operator recipes

`services up run` and similar commands require the full tuple. `cell.nu`
validates the tuple against matrix rules and refuses mismatches.

### Two-party (contact-token, share-with, contact-wayf)

```sh
nu scripts/ocmts.nu services up run \
  --flow <flow_id> \
  --sender-platform <sp> --sender-version <sv> \
  --receiver-platform <rp> --receiver-version <rv>
```

Example: ocis -> opencloud contact-token

```sh
nu scripts/ocmts.nu services up run \
  --flow contact-token \
  --sender-platform ocis --sender-version v8 \
  --receiver-platform opencloud --receiver-version v6
```

Example: nextcloud -> nextcloud share-with

```sh
nu scripts/ocmts.nu services up run \
  --flow share-with \
  --sender-platform nextcloud --sender-version v33 \
  --receiver-platform nextcloud --receiver-version v33
```

### One-party (login)

```sh
nu scripts/ocmts.nu services up run \
  --flow login \
  --sender-platform <sp> --sender-version <sv>
```

Example: ocis login

```sh
nu scripts/ocmts.nu services up run \
  --flow login \
  --sender-platform ocis --sender-version v8
```

## Actor overrides

Per-cell actor bindings live under `config/actors/overrides/<matrix_key>.nuon`.
Example: `config/actors/overrides/share-with__nextcloud__ocmgo.nuon`.

List overrides:

```sh
nu scripts/ocmts.nu actors list overrides
```

## Regenerating the live matrix table

From the repo root:

```sh
nu -c 'use scripts/lib/matrix/rules-gen.nu [load-matrix-rules matrix-key]; let r = (load-matrix-rules (pwd)); $r.matrix | items {|k, v| { matrix_key: $k, flow: $v.flow_id, sender: $v.sender.platform, sender_v: ($v.sender.version_lines | str join ", "), receiver: ($v.receiver?.platform? | default "-"), receiver_v: ($v.receiver?.version_lines? | default [] | str join ", ") }} | sort-by flow matrix_key | to md --pretty'
```

## Gotchas

- **`flow_id` alone is not enough.** You must pass sender (and receiver for
  two-party flows) platform and version on the CLI.
- **`matrix_key` uses platform names, not versions.** Versions appear only
  in `cell_id`, artifact paths, and CLI version flags.
- **Cypress module paths use `scenario_module` (= `flow_id`).** Each module's
  generated `matrix.ts` lists enabled `cell_id` values in `matrixCellIds`.
  Regenerate with `nu scripts/ocmts.nu matrix gen cypress` after matrix rule
  changes; `matrix gen cypress --check` verifies on-disk files match.
