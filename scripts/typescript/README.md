# scripts/typescript/ - TypeScript sidecars

TypeScript lives here when Nushell can't reach the answer cheaply. Today
that means walking the Cypress TypeScript AST to validate adapter
capabilities. Bun is the runtime; no compile step.

```text
scripts/typescript/check-adapter-capabilities.ts  # adapter-registry vs JSON drift check
```

## Run

From the repo root:

```sh
bun run scripts/typescript/check-adapter-capabilities.ts
```

The script prints `[check-adapter-capabilities] OK` on stdout and exits 0
when the adapter registry matches the JSON capability table. On drift it
prints a structured diff to stderr and exits 1; on internal errors it
exits 2.

The script resolves the repo root in this order:

1. `OCMTS_ROOT` env var (set by CI to `${{ github.workspace }}`).
2. Walk up two levels from the script's own location (works for local
   `bun run scripts/typescript/...` from the repo root).

CI wires it as a `preflight` job in
`scripts/lib/ci/blueprints/github/workflows/ci-matrix.yml.tpl`. Setup,
flow jobs, aggregation, and site publishing all transitively depend on
preflight passing.

## Conventions

- One concern per file. Split into `lib/<area>/<topic>.ts` modules if a
  file grows multiple responsibilities.
- Bun-first: `bun run <file>.ts` for execution, `bun install` for
  dependencies (`bun.lock` is the source of truth; `package-lock.json`
  must not exist alongside it).
- TypeScript dependencies that are runtime-needed go in `package.json`'s
  `devDependencies` (the suite has no production runtime - everything is
  CI-time tooling). Pin versions; `bun install --frozen-lockfile` runs in
  CI and will fail on lockfile drift.
- Type-check sidecars by including their tree in the repo's
  `tsconfig.json`. There is no separate tsconfig for `scripts/typescript/`.

## Adding a file

1. Place it under `scripts/typescript/<name>.ts` or
   `scripts/typescript/lib/<area>/<topic>.ts`.
2. Confirm it picks up `tsconfig.json` (the `include` array covers this
   tree).
3. If it should run in CI, add a job (or extend the preflight) in the
   appropriate blueprint under `scripts/lib/ci/blueprints/`.
4. Update this README so the next agent can find it.
