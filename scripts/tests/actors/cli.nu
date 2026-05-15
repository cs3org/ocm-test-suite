# Actor CLI smoke tests.
# Run: nu scripts/tests/actors/cli.nu
# Exercises the `actors list` and `actors list overrides` verbs against the
# real repo root. get-ocmts-root resolves via git when run from within the
# repo, so this test must be run from inside the ots-rebooted repo tree.

const SUITE_PATH = path self

use ../../lib/tests/assert.nu *
use ../../lib/tests/runner.nu [run-suite]

# Derive repo root from this file's own location.
def repo-root [] {
    $SUITE_PATH | path dirname | path dirname | path dirname | path dirname
}

# `actors list` exits 0 and prints at least one matrix-enabled scenario.
def test-actors-list [] {
    test-log "\n[test-actors-list]"
    let root = (repo-root)
    let out = (^nu ($root | path join "scripts/ocmts.nu") actors list | complete)
    [
        (assert-eq $out.exit_code 0
            "actors list exits 0")
        (assert-string-contains $out.stdout "login"
            "actors list output contains 'login'")
    ]
}

# `actors list overrides` exits 0 (may print nothing if no override files).
def test-actors-list-overrides [] {
    test-log "\n[test-actors-list-overrides]"
    let root = (repo-root)
    let out = (^nu ($root | path join "scripts/ocmts.nu") actors list overrides | complete)
    [
        (assert-eq $out.exit_code 0
            "actors list overrides exits 0")
    ]
}

def main [] {
    test-log "=== actors/cli Tests ==="
    let results = (
        (test-actors-list)
        | append (test-actors-list-overrides)
    ) | flatten
    run-suite "actors/cli" $SUITE_PATH $results
}
