# scripts/tests/ - Nushell unit test suites

These are Nushell **unit** tests for the `ocmts` CLI library code under
`scripts/lib/` and `scripts/domains/`. They are NOT the Cypress
end-to-end integration tests. Cypress E2E specs live in `cypress/` at
the repo root and are invoked via `ocmts test cypress run` (single
cell) or `ocmts test cypress suite` (full matrix). The two test trees
exist for different purposes and never overlap.

Each file here is a self-contained suite that can be run on its own.
Suites are organized by subject area at `scripts/tests/<area>/<topic>.nu`
so each test sits next to the `lib/` module it exercises. Shared
assertion, runner, and fixture helpers live in `scripts/lib/tests/`;
suites import them and stay focused on the behaviors they exercise.

## Run a suite

From the repo root, the preferred entrypoint is the `ocmts` CLI:

```sh
nu scripts/ocmts.nu test units                              # all suites, combined JSON
nu scripts/ocmts.nu test units --suite <area/topic>         # one suite, e.g. ci/planner
nu scripts/ocmts.nu test units --list                       # list available suites
nu scripts/ocmts.nu test units --human                      # human-friendly mode
```

The lower-level invocations still work for direct file access:

```sh
nu scripts/tests/<area>/<topic>.nu                    # human output
OCMTS_TEST_JSON=1 nu scripts/tests/<area>/<topic>.nu  # machine output
nu scripts/tests/run-all.nu                           # run every suite, combined JSON
```

In human mode each suite prints a per-test header, per-assert
`ok:`/`FAIL:` lines, and a `=== <suite>: <passed>/<total> passed ===`
summary; it exits 0 on all-pass and 1 on any failure.

In JSON mode each suite emits a single JSON object on stdout:

```json
{"suite":"<area>/<topic>","path":"/abs/path/.../topic.nu","status":"pass","total":N,"passed":N,"failed":0,"failures":[]}
```

`path` is the absolute path to the suite file. `status` is `"pass"` or
`"fail"`. The `suite` field mirrors the directory layout (e.g.
`ci/planner` for `tests/ci/planner.nu`). Exit code is 1 when
`failed > 0`, 0 otherwise.

`run-all.nu` runs every suite and emits one combined record:

```json
{"suites":N,"total":N,"passed":N,"failed":0,"status":"pass","results":[{<per-suite record>},...]}
```

## Current suites

- `ci/planner.nu` - exercises `lib/ci/planner.nu`, `lib/ci/blocker.nu`,
  flow ordering. (210 asserts.)
- `matrix/topology.nu` - exercises `lib/matrix/topology.nu` and
  topology-consistency cross-checks. (8 asserts.)
- `mitm/dispatcher.nu` - exercises
  `lib/mitm/validator-dispatcher.nu`. (36 asserts.)
- `ocm/endpoints.nu` - exercises `lib/ocm/endpoints.nu` (endpoint
  resolution). (90 asserts.)
- `publish/envelope.nu` - exercises `lib/publish/envelope.nu`. (76
  asserts.)
- `run/finalize.nu` - exercises `lib/run/finalize.nu` (run
  finalization). (62 asserts.)
- `run/metadata.nu` - exercises `lib/run/metadata.nu` and the
  stop-on-fail tail helper. (41 asserts.)
- `site/cell-impl.nu` - exercises `lib/site/cell-impl.nu`. (27
  asserts.)
- `site/clone.nu` - exercises the suite-level publish path
  (`lib/site/clone.nu`). (11 asserts.)

## Why these exist

These suites are designed for agentic development, not CI. The goal is:

- Fast local feedback when a `lib/` module changes.
- Deterministic, structured assertions so an agent can tell signal from
  noise without scraping prose.
- Each suite is independently runnable so an agent can target the
  smallest relevant blast radius.
- A `OCMTS_TEST_JSON=1` machine mode so an agent can consume results
  programmatically without parsing console prose.

## Conventions

- Import the module under test with
  `use ../../lib/<path>.nu [<symbols>]`. Do not import via
  `domains/...` unless the test specifically covers a CLI surface.
- Import shared test infrastructure with the standard preamble below
  (drop `fixtures.nu` if the suite does not need tmp dirs):

  ```nu
  use ../../lib/tests/assert.nu *
  use ../../lib/tests/runner.nu [run-suite]
  use ../../lib/tests/fixtures.nu [with-tmp-dir]
  ```

- Declare `const SUITE_PATH = path self` at the top of each suite
  (parse-time only; required by `run-suite`):

  ```nu
  const SUITE_PATH = path self
  ...
  run-suite "<area>/<topic>" $SUITE_PATH $results
  ```

- Available asserts in `lib/tests/assert.nu`:
  - `assert-eq got want label`
  - `assert-truthy got label`
  - `assert-null got label`
  - `assert-not-null got label`
  - `assert-string-contains got sub label`
  - `assert-list-contains got item label`
  - `assert-list-not-contains got item label`
- Each `def test-foo []` returns a list of assert results. The `main`
  collects them with `... | flatten` and hands them to
  `run-suite "<area>/<topic>" $SUITE_PATH $results`.
- Use `with-tmp-dir { |tmp| ... }` instead of bare `mktemp -d` +
  `^rm -rf`; cleanup is guaranteed even on assert failure.
- Prefer behavior assertions (call the function, check the returned
  shape and values) over source-text greps.
- Banner prints inside a test should go through `test-log` from
  `assert.nu` so JSON mode stays clean (it suppresses the banner when
  `OCMTS_TEST_JSON=1`).
