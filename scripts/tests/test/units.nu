# CLI contract tests for `ocmts test units`.
# Covers --list, --include-manual guard, manual-suite blocking, --suite
# JSON mode, --suites combined JSON, --suites --human, and human-mode guard.
# Run: nu scripts/tests/test/units.nu

const SUITE_PATH = path self

use ../../lib/tests/assert.nu *
use ../../lib/tests/runner.nu [run-suite]

# Thin wrapper so callers pass flags naturally via --wrapped.
def --wrapped run-units [...args: string] {
    ^nu "scripts/ocmts.nu" "test" "units" ...$args | complete
}

def test-list-excludes-manual [] {
    test-log "\n[test-list-excludes-manual]"
    let r = (run-units --list)
    let lines = ($r.stdout | lines | where {|l| not ($l | str trim | is-empty)})
    let has_manual = ($lines | any {|l| $l | str contains "integration/manual/"})
    [
        (assert-eq $r.exit_code 0 "--list exits 0")
        (assert-truthy (not $has_manual) "--list output has no integration/manual/ entries")
    ]
}

def test-list-include-manual [] {
    test-log "\n[test-list-include-manual]"
    let r = (run-units --list --include-manual)
    let lines = ($r.stdout | lines | where {|l| not ($l | str trim | is-empty)})
    let has_manual = ($lines | any {|l| $l | str contains "integration/manual/"})
    [
        (assert-eq $r.exit_code 0 "--list --include-manual exits 0")
        (assert-truthy $has_manual "--list --include-manual output includes at least one integration/manual/ entry")
    ]
}

def test-manual-suite-blocked-without-flag [] {
    test-log "\n[test-manual-suite-blocked-without-flag]"
    let r = (run-units --suite "integration/manual/optimized-media-real-ffmpeg")
    [
        (assert-eq $r.exit_code 1 "manual suite without --include-manual exits 1")
        (assert-truthy ($r.stderr | str contains "--include-manual")
            "stderr mentions --include-manual")
        (assert-truthy ($r.stderr | str contains "manual suite")
            "stderr says 'manual suite'")
    ]
}

def test-suite-single-json [] {
    test-log "\n[test-suite-single-json]"
    let r = (run-units --suite "run/utc")
    let last_line = ($r.stdout | lines | where {|l| not ($l | str trim | is-empty)} | last)
    let parsed = (try { $last_line | from json } catch { null })
    [
        (assert-eq $r.exit_code 0 "--suite run/utc exits 0")
        (assert-truthy ($parsed != null) "stdout is valid JSON")
        (assert-eq ($parsed.status? | default "") "pass" "suite status is 'pass'")
        (assert-truthy (($parsed.total? | default 0) > 0) "suite total > 0")
    ]
}

def test-suites-combined-json [] {
    test-log "\n[test-suites-combined-json]"
    let r = (run-units --suites "run/utc,run/status")
    let last_line = ($r.stdout | lines | where {|l| not ($l | str trim | is-empty)} | last)
    let parsed = (try { $last_line | from json } catch { null })
    [
        (assert-eq $r.exit_code 0 "--suites run/utc,run/status exits 0")
        (assert-truthy ($parsed != null) "stdout is valid JSON")
        (assert-eq ($parsed.suites? | default 0) 2 "aggregate suites count is 2")
        (assert-truthy (($parsed.total? | default 0) > 0) "aggregate total > 0")
        (assert-truthy ($parsed.passed? != null) "aggregate has 'passed' field")
        (assert-truthy ($parsed.failed? != null) "aggregate has 'failed' field")
        (assert-truthy ($parsed.results? != null) "aggregate has 'results' field")
        (assert-eq ($parsed.status? | default "") "pass" "aggregate status is 'pass'")
    ]
}

def test-suites-human-mode [] {
    test-log "\n[test-suites-human-mode]"
    let r = (run-units --suites "run/utc,run/status" --human)
    let out = ($r.stdout | str trim)
    [
        (assert-eq $r.exit_code 0 "--suites --human exits 0")
        (assert-truthy (not ($out | str starts-with "{")) "--human stdout is not a JSON object")
    ]
}

# Guard: --human on the run path does not silently stay JSON-only.
# Uses --suites with a small suite to exercise run-suites-human (same
# branch as the default all-suites path) without running all suites.
def test-human-flag-not-suppressed [] {
    test-log "\n[test-human-flag-not-suppressed]"
    let r = (run-units --suites "run/utc" --human)
    let out = ($r.stdout | str trim)
    let is_json_aggregate = (
        try {
            let p = ($out | from json)
            (($p.suites? != null) or ($p.suite? != null))
        } catch { false }
    )
    [
        (assert-eq $r.exit_code 0 "--suites --human exits 0")
        (assert-truthy (not $is_json_aggregate)
            "--human does not emit a JSON aggregate (human streaming is active)")
    ]
}

def main [] {
    test-log "=== test/units CLI contract tests ==="
    let results = (
        (test-list-excludes-manual)
        | append (test-list-include-manual)
        | append (test-manual-suite-blocked-without-flag)
        | append (test-suite-single-json)
        | append (test-suites-combined-json)
        | append (test-suites-human-mode)
        | append (test-human-flag-not-suppressed)
    ) | flatten
    run-suite "test/units" $SUITE_PATH $results
}
