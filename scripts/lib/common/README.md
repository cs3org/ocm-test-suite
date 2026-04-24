# common/

Small generic helpers shared across domains in ocmts.

## Files

- `complete-record.nu` - Operate on the record produced by `| complete` on
  external commands. Exports `complete-ok`, `complete-stdout`,
  `complete-or-fail`.

- `stderr-match.nu` - Case-insensitive substring helpers for stderr strings.
  Exports `stderr-contains`, `stderr-matches-any`, `stderr-first-match`.

## Example

Before (raw `complete` boilerplate):

    let r = (^docker compose ...$f_args ps | complete)
    if $r.exit_code != 0 {
        print --stderr $"compose ps failed: ($r.stderr | str trim)"
        exit 2
    }
    let services = ($r.stdout | str trim | lines)

After (with `complete-record`):

    use ../common/complete-record.nu [complete-stdout]
    let services = (^docker compose ...$f_args ps | complete | complete-stdout | lines)

The `complete-or-fail` variant is for fire-and-forget calls where you want a
one-liner that prints and exits on failure:

    use ../common/complete-record.nu [complete-or-fail]
    ^docker compose ...$f_args pull | complete | complete-or-fail "pull failed"

## Vendor note

These files are literal copies of MAIDE helpers from
`/root/projects/ocm/sta/scripts/lib/common/` (the MAIDE workspace). ocmts is
policy-bound to be independent of MAIDE source, so do not import or symlink
across repos. If you find a real bug in this copy, fix it here first; if MAIDE
has the same bug or a relevant upgrade, manually port it over. The copies are
intentionally simple and stable.

## Adoption

Call-site adoption is opportunistic: refactor existing scripts as files are
touched rather than a Wave-2 sweep. Wave 3 (lib reorg) is the next natural
opportunity for any bulk-change pass.
