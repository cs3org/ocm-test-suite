# scripts/ - OCM Test Suite automation

Public CLI entrypoint and supporting Nushell modules for the OCM test suite.
Run everything from the repo root:

```sh
nu scripts/ocmts.nu <domain> [<verb>...] [flags]
nu scripts/ocmts.nu          # top-level usage
nu scripts/ocmts.nu <domain> # per-domain usage
```

For the flat map of every `domain verb` pair, see
[`ocmts-command-map.md`](./ocmts-command-map.md).

## Layout

```text
scripts/
  ocmts.nu                 # public CLI router (thin; only `forward-to`)
  domains/                 # one folder per CLI domain
    actors/                # mod.nu (verbs inline; small, single-file domain)
    artifacts/             # mod.nu (router) + list/show/collect/publish/prune.nu
    ci/                    # mod.nu (router) + plan/aggregate/emit-blocked.nu
                           #                 + workflows-{generate,check}-github.nu
    images/    matrix/     # mod.nu (verbs inline; smaller domains)
    services/              # mod.nu (router) + up/up-run/up-open/down.nu
    site/                  # mod.nu (verbs inline; includes site preview)
    test/                  # mod.nu (router) splits CYPRESS vs UNITS:
                           #   cypress-run.nu, cypress-suite.nu (E2E)
                           #   units.nu (Nushell unit-test runner wrapper)
    version/               # mod.nu (one-shot)
  lib/                     # implementation modules (no top-level `main`)
    domain/core/           # CLI primitives (forward-to, root resolution)
    common/                # generic helpers (complete-record, stderr-match)
    actors/                # credentials, resolve, load (tuple loaders for
                           # actor/sender/receiver; list keys via
                           # list-matrix-keys or list-override-files),
                           # validate
    artifacts/             # init, prune
    ci/                    # planner, blocker, aggregator, workflow-gen,
                           # template-renderer, flow-order, suite-stop-on-fail
    compose/               # render, validate, logs, yaml, topology-common
                           # (shared helpers), topology-{one,two}-party
    images/                # precedence (env-override + 6/11-level resolvers),
                           # config (load + list + validate), resolve (the
                           # public sender/receiver/mitmproxy resolvers)
    matrix/                # cell, cells, expand, rules-gen, cypress-gen,
                           # topology (canonical two_party SSOT)
    mitm/                  # summary, ocm-summary, peers, report-utils,
                           # validator-dispatcher, code-flow-validator
    ocm/                   # endpoints
    publish/               # envelope, evidence (per-cell sidecar emitters)
    run/                   # execution-id, finalize, flow-ids, metadata,
                           # result-envelope, status
    services/              # compose-files, context, cypress-run,
                           # lifecycle, postrun-artifacts
    site/                  # blocker-logic, build, cell-impl, clone,
                           # config, copy, flow-caps, ingest, internal
                           # (shared private helpers), manifest, preview,
                           # project-media, provenance, publish
    suite/                 # index
    tests/                 # assert, runner, fixtures (test-suite helpers)
  tests/                   # Nushell test suites organized by area
                           # (ci/, matrix/, mitm/, ocm/, publish/, run/, site/)
                           # plus run-all.nu aggregator; see tests/README.md
  python/                  # Python sidecars; see python/README.md
    lib/mitm/mitmproxy_jsonl.py   # mitmproxy addon (bind-mounted)
  typescript/              # TypeScript sidecars; see typescript/README.md
    extract-registry-keys.ts     # AST dumper for Cypress adapter registry
  ocmts-command-map.md     # flat reference of every CLI verb
```

Every `lib/` module lives under a topic subdirectory; there are no flat
`lib/*.nu` files. When two siblings share a small private helper, put it
in a sibling `internal.nu` (see `lib/site/internal.nu`) or a dedicated
`-common.nu` module (see `lib/compose/topology-common.nu`) and import
from there; do NOT copy-paste `def`s across files. Avoid adding new flat
`lib/*.nu` files - place them under the matching subdirectory instead.

## Routing model

`scripts/ocmts.nu` is intentionally a thin router. Each `def --wrapped
"main <domain>"` calls `forward-to "scripts/domains/<domain>/mod.nu" $args`,
which spawns a child `nu` process and forwards stdout, stderr, and exit
code.

Domain `mod.nu` files come in two shapes depending on size:

- **Small domains** (e.g. `actors/`, `images/`, `matrix/`, `site/`,
  `version/`) keep verb implementations inline. `def "main <verb>"`
  definitions own argument parsing, defaults, and behavior directly.
- **Large domains** (`test/`, `services/`, `ci/`, `artifacts/`) use a
  second forward-to layer: `mod.nu` is a thin router that prints usage
  help and forwards each verb to a sibling per-verb file via
  `def --wrapped "main <verb>" [...args: string] { forward-to
  "scripts/domains/<area>/<verb>.nu" $args }`. The verb file owns the
  flag declarations, imports, and implementation.
- The `test/` domain takes routing one step further: it has a `cypress`
  sub-namespace (`test cypress run`, `test cypress suite`) for
  end-to-end Docker-driven tests, and a flat `units` verb for the
  internal Nushell unit-test runner. The verb path itself is the
  disambiguator so "tests" never collapse into one ambiguous word.

Per-verb files use flat hyphenated names for multi-word verbs
(`up-run.nu` for `services up run`, `workflows-generate-github.nu` for
`ci workflows generate github`) so the file tree mirrors verb names
without nested directories.

Helpers under `lib/` MUST NOT define a top-level `main`. They are imported
with `use ../../lib/<area>/<name>.nu [<symbols>]` from a verb file (or
`use ../lib/<area>/<name>.nu [...]` from a router). This keeps `lib/`
reusable across domains and tests.

## Mixed languages

Nushell is the default. Other languages live in dedicated sidecar trees so
each language has a clean home:

- `scripts/python/` - Python addons and helpers. See
  [`python/README.md`](./python/README.md). Today: the mitmproxy addon at
  `python/lib/mitm/mitmproxy_jsonl.py`, bind-mounted into the MITM
  container by the compose topology generator.
- `scripts/typescript/` - TypeScript sidecars for things Nushell can't
  cheaply reach. See [`typescript/README.md`](./typescript/README.md).
  Today: `extract-registry-keys.ts`, a tiny AST dumper that walks the
  Cypress adapter registry and emits its table keys as JSON; the full
  adapter drift check is `nu scripts/ocmts.nu matrix check capabilities`,
  which calls this helper internally. The CI preflight job invokes the
  nu CLI verb directly from
  `scripts/lib/ci/blueprints/github/workflows/ci-matrix.yml.tpl`.

Do not add `.py` or `.ts` files directly under `scripts/`. Place them in
the matching sidecar tree.

## Conventions

- Subprocess calls go through `lib/domain/core/nu-forward.nu::forward-to`
  for child Nushell commands; for `^docker`, `^git`, etc., wrap with `|
  complete` and check `$env.LAST_EXIT_CODE` or `$result.exit_code`.
- Resolve the repo root via `lib/domain/core/ocmts-root.nu::get-ocmts-root`;
  do not hardcode paths.
- Errors that should stop the pipeline use `error make {msg: "..."}`. Errors
  that should be reported but not abort go through `print --stderr ...`
  with a deliberate exit code.
- Test files live under `tests/` and import the modules they exercise
  directly; see [`tests/README.md`](./tests/README.md).
