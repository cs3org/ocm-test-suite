# Scenario Keys

`flow_id` and `scenario_key` are NOT the same thing. The CLI's `--scenario`
flag and almost every internal validator (`scripts/lib/matrix/cell.nu`,
the actor loaders, `cypress-gen.nu`, the suite planner) take a scenario
key, not a flow id. Mixing them up produces errors like:

```text
Error: Sender platform 'ocis' not valid for scenario 'contact-token'.
       Expected: nextcloud
```

This doc is the single source of truth for how scenario keys are formed
and how to map a (flow, sender, receiver) tuple to one.

## Vocabulary

| Term            | Definition                                                                 |
| --------------- | -------------------------------------------------------------------------- |
| `flow_id`       | Public flow name. Five exist today: `login`, `share-with`, `contact-token`, `contact-wayf`, `code-flow`. Stable across versions and pairs. |
| `scenario_key`  | Per-pair routable key. One per (flow, sender_platform, receiver_platform) combo. What `--scenario` accepts. |
| `cell_id`       | Per-pair, per-version artifact id. Shape `<flow_id>__<sender_platform>-<sender_version>[__<receiver_platform>-<receiver_version>]`. |
| `pair`          | Role-ordered, opaque artifact path segment. One-party: `<sender_platform>-<sender_version>`. Two-party: `<sender>-<sver>-<recv>-<rver>`. |

The flow id is what users say in conversation ("the contact-token flow");
the scenario key is what the CLI consumes; the cell id is what the
artifact directory and matrix UI show.

## Naming Convention

Defined in `scripts/lib/matrix/rules-gen.nu::scenario-key`. Inputs:

- `flow_id`
- `sender` platform name (e.g., `nextcloud`, `ocis`, `opencloud`, `ocmgo`)
- `receiver` platform name, or `null` for one-party flows
- `baseline` from `config/matrix/naming.nuon::baseline_by_flow.<flow_id>`
- `slug` from `config/matrix/platforms.nuon::platforms.<name>.slug`

Resolution rules (in order):

1. If `(sender, receiver) == (baseline.sender, baseline.receiver)` for
   this flow, the key is the bare `<flow_id>`.
2. Else if the flow is one-party (`receiver == null`), the key is
   `<flow_id>-<sender_slug>`.
3. Else (two-party, non-baseline) the key is
   `<flow_id>-<sender_slug>-<receiver_slug>`.
4. `naming.nuon::overrides[<raw_key>]` may remap the result. Currently
   empty.

### Slugs

From `config/matrix/platforms.nuon`:

| Platform   | Slug        |
| ---------- | ----------- |
| nextcloud  | `nc`        |
| ocis       | `ocis`      |
| opencloud  | `opencloud` |
| ocmgo      | `ocmgo`     |

### Baselines

From `config/matrix/naming.nuon::baseline_by_flow`:

| Flow            | Baseline sender | Baseline receiver |
| --------------- | --------------- | ----------------- |
| `login`         | nextcloud       | (none, one-party) |
| `share-with`    | nextcloud       | nextcloud         |
| `contact-token` | nextcloud       | nextcloud         |
| `contact-wayf`  | nextcloud       | nextcloud         |
| `code-flow`     | nextcloud       | nextcloud         |

## Live scenario key table

This table is regenerable; do not hand-edit. It is the output of
`load-matrix-rules` on the current `config/matrix/` SSOT.

| Scenario key                        | Flow            | Sender      | Sender version  | Receiver    | Receiver version |
| ----------------------------------- | --------------- | ----------- | --------------- | ----------- | ---------------- |
| `contact-token`                     | `contact-token` | nextcloud   | v34             | nextcloud   | v34              |
| `contact-token-nc-ocis`             | `contact-token` | nextcloud   | v34             | ocis        | v8               |
| `contact-token-nc-opencloud`        | `contact-token` | nextcloud   | v34             | opencloud   | v6               |
| `contact-token-ocis-nc`             | `contact-token` | ocis        | v8              | nextcloud   | v34              |
| `contact-token-ocis-ocis`           | `contact-token` | ocis        | v8              | ocis        | v8               |
| `contact-token-ocis-opencloud`      | `contact-token` | ocis        | v8              | opencloud   | v6               |
| `contact-token-opencloud-nc`        | `contact-token` | opencloud   | v6              | nextcloud   | v34              |
| `contact-token-opencloud-ocis`      | `contact-token` | opencloud   | v6              | ocis        | v8               |
| `contact-token-opencloud-opencloud` | `contact-token` | opencloud   | v6              | opencloud   | v6               |
| `contact-wayf`                      | `contact-wayf`  | nextcloud   | v34             | nextcloud   | v34              |
| `login`                             | `login`         | nextcloud   | v32, v33, v34   | -           |                  |
| `login-ocis`                        | `login`         | ocis        | v8              | -           |                  |
| `login-ocmgo`                       | `login`         | ocmgo       | v1              | -           |                  |
| `login-opencloud`                   | `login`         | opencloud   | v6              | -           |                  |
| `share-with`                        | `share-with`    | nextcloud   | v32, v33, v34   | nextcloud   | v32, v33, v34    |
| `share-with-nc-ocmgo`               | `share-with`    | nextcloud   | v32, v33, v34   | ocmgo       | v1               |
| `share-with-ocmgo-nc`               | `share-with`    | ocmgo       | v1              | nextcloud   | v32, v33, v34    |
| `share-with-ocmgo-ocmgo`            | `share-with`    | ocmgo       | v1              | ocmgo       | v1               |

`code-flow` is currently `enabled: false` in `config/matrix/flows/` and
emits no scenario keys.

To regenerate the table from the SSOT:

```sh
cd repos/ots-rebooted
nu -c "use scripts/lib/matrix/rules-gen.nu [load-matrix-rules]; \
  let r = (load-matrix-rules (pwd)); \
  \$r.scenarios | items {|k, v| { \
    key: \$k, flow: \$v.flow_id, \
    sender: \$v.sender.platform, \
    sender_v: (\$v.sender.version_lines | str join ', '), \
    receiver: (\$v.receiver?.platform? | default '-'), \
    receiver_v: (\$v.receiver?.version_lines? | default [] | str join ', ') \
  }} | sort-by flow key | to md --pretty"
```

## Operator Recipes

`services up run` and similar commands take BOTH `--scenario` AND the
explicit `--sender-platform` / `--sender-version` (and receiver pair for
two-party flows). The pair MUST match what the scenario key declares;
`cell.nu` validates and refuses mismatches.

### Two-party (contact-token, share-with, contact-wayf, code-flow)

```sh
nu scripts/ocmts.nu services up run --scenario <scenario_key> \
  --sender-platform <sp> --sender-version <sv> \
  --receiver-platform <rp> --receiver-version <rv>
```

Concrete: ocis -> opencloud contact-token

```sh
nu scripts/ocmts.nu services up run --scenario contact-token-ocis-opencloud \
  --sender-platform ocis --sender-version v8 \
  --receiver-platform opencloud --receiver-version v6
```

Concrete: nextcloud -> nextcloud share-with (baseline)

```sh
nu scripts/ocmts.nu services up run --scenario share-with \
  --sender-platform nextcloud --sender-version v33 \
  --receiver-platform nextcloud --receiver-version v33
```

### One-party (login)

```sh
nu scripts/ocmts.nu services up run --scenario <scenario_key> \
  --sender-platform <sp> --sender-version <sv>
```

Concrete: ocis login

```sh
nu scripts/ocmts.nu services up run --scenario login-ocis \
  --sender-platform ocis --sender-version v8
```

## Gotchas

- **The bare flow_id only routes for the baseline pair.** Calling
  `--scenario contact-token` with anything other than nextcloud->nextcloud
  fails with a "platform not valid for scenario" error.
- **`nc` (slug) is not the same as `nextcloud` (platform name).** Slugs
  appear in scenario keys; platform names appear in CLI flags, cell ids,
  artifact paths.
- **Scenario keys can be remapped via `naming.nuon::overrides`.** Always
  generate the live table from `load-matrix-rules` rather than computing
  it from first principles.
- **Cell ids use platform names, not slugs.** Example:
  scenario `contact-token-ocis-opencloud` -> cell id
  `contact-token__ocis-v8__opencloud-v6`.
