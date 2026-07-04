# scripts/python/ - Python sidecars

Python lives here when Nushell can't (or shouldn't) do the job. The current
inhabitants are addons and helpers that run inside containers, not on the
host. Mirror this folder's tree against the role of each file:

```text
scripts/python/
  lib/
    mitm/
      mitmproxy_jsonl.py   # mitmproxy addon, bind-mounted into the MITM
                           # container; never runs on the host directly
```

## Conventions

- File names use `snake_case.py` (Python convention) so module imports
  stay predictable; do not use `kebab-case` here even if the parent area
  uses it for `.nu` files.
- One concern per file. If a script grows multiple responsibilities, split
  into a `lib/<area>/<topic>.py` module and a thin entrypoint.
- Standard-library only when possible. If you need a third-party package,
  document it in this README and pin a version in the place that installs
  it (container image, CI step, etc.).
- Host execution is rare. Most files here are bind-mounted into a
  container; the Nushell side wires the mount in
  `scripts/lib/compose/<topology>.nu`.

## Adding a file

1. Place it under `lib/<area>/<topic>.py`.
2. If it's bind-mounted, update the relevant `topology-*.nu` to point at
   the new path AND the in-container target name.
3. Update this README's tree above so the next agent can find it.
