# scripts/typescript/ - TypeScript sidecars

TypeScript lives here when Nushell can't reach the answer cheaply. Today
that means walking the Cypress TypeScript AST to extract adapter registry
keys. Bun is the runtime; no compile step.

```text
extract-registry-keys.ts  # AST dumper: registry.ts table keys -> JSON
```

## Files

### extract-registry-keys.ts

Accepts one CLI arg: path to a Cypress `registry.ts` source file.

```sh
bun run scripts/typescript/extract-registry-keys.ts \
  cypress/support/adapters/registry.ts
```

Stdout: a single-line JSON record. Keys are the 8 adapter table names
found in `cypress/support/adapters/registry.ts`:

- `loginAdapters`
- `shareWithSenderAdapters`
- `shareWithReceiverAdapters`
- `contactTokenSenderAdapters`
- `contactTokenReceiverAdapters`
- `contactWayfSenderAdapters`
- `contactWayfReceiverAdapters`
- `providerIdentityAdapters`

Each value is a sorted array of `"<platform>/<version>"` strings.

Exit codes: `0` on success, `2` on argument or parse error (one-line
message to stderr).

This is a pure AST dumper; it knows nothing about capabilities, schemas,
or matrices. Its only consumer is `nu scripts/ocmts.nu matrix check
capabilities`, which performs the actual drift logic in Nushell.

The full adapter-capabilities drift check runs via:

```sh
nu scripts/ocmts.nu matrix check capabilities
```

That command calls this helper internally, then composes its output with
platform, capability, flow, and provenance checks in Nushell. CI runs
the same command in the preflight job.

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
3. If it should run in CI, add a job (or extend an existing CI job) in
   the appropriate blueprint under `scripts/lib/ci/blueprints/`.
4. Update this README so the next agent can find it.
