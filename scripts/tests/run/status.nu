# Canonical unit tests for scripts/lib/run/status.nu run-status-precedence.
# All precedence coverage lives here; wrappers in other suites only do one
# thin delegation assertion each.
# Run: nu scripts/tests/run/status.nu

const SUITE_PATH = path self

use ../../lib/run/status.nu [run-status-precedence]
use ../../lib/tests/assert.nu *
use ../../lib/tests/runner.nu [run-suite]

def test-failed-wins-over-all [] {
    test-log "\n[test-failed-wins-over-all]"
    [
        (assert-eq (run-status-precedence ["failed"]) "failed"
            "single failed -> failed")
        (assert-eq (run-status-precedence ["infra-failed"]) "failed"
            "infra-failed -> failed")
        (assert-eq (run-status-precedence ["cleanup-failed"]) "failed"
            "cleanup-failed -> failed")
        (assert-eq (run-status-precedence ["failed" "passed" "running" "blocked" "missing"]) "failed"
            "failed beats all others")
        (assert-eq (run-status-precedence ["infra-failed" "running" "blocked"]) "failed"
            "infra-failed beats running and blocked")
        (assert-eq (run-status-precedence ["cleanup-failed" "blocked"]) "failed"
            "cleanup-failed beats blocked")
    ]
}

def test-running-beats-blocked-missing-passed [] {
    test-log "\n[test-running-beats-blocked-missing-passed]"
    [
        (assert-eq (run-status-precedence ["running"]) "running"
            "single running -> running")
        (assert-eq (run-status-precedence ["passed" "running" "blocked"]) "running"
            "running beats blocked and passed")
        (assert-eq (run-status-precedence ["missing" "running"]) "running"
            "running beats missing")
    ]
}

def test-blocked-beats-missing-passed [] {
    test-log "\n[test-blocked-beats-missing-passed]"
    [
        (assert-eq (run-status-precedence ["blocked"]) "blocked"
            "single blocked -> blocked")
        (assert-eq (run-status-precedence ["passed" "blocked" "missing"]) "blocked"
            "blocked beats missing and passed")
    ]
}

def test-missing-beats-passed [] {
    test-log "\n[test-missing-beats-passed]"
    [
        (assert-eq (run-status-precedence ["missing"]) "missing"
            "single missing -> missing")
        (assert-eq (run-status-precedence ["passed" "missing"]) "missing"
            "missing beats passed")
    ]
}

def test-passed-all-equal [] {
    test-log "\n[test-passed-all-equal]"
    [
        (assert-eq (run-status-precedence ["passed" "passed" "passed"]) "passed"
            "all passed -> passed")
        (assert-eq (run-status-precedence ["passed"]) "passed"
            "single passed -> passed")
    ]
}

def test-empty-list [] {
    test-log "\n[test-empty-list]"
    [
        (assert-eq (run-status-precedence []) "passed"
            "empty list -> passed")
    ]
}

def test-capability-skipped-transparent [] {
    test-log "\n[test-capability-skipped-transparent]"
    [
        (assert-eq (run-status-precedence ["capability-skipped"]) "passed"
            "all capability-skipped -> passed")
        (assert-eq (run-status-precedence ["passed" "capability-skipped"]) "passed"
            "passed + capability-skipped -> passed")
        (assert-eq (run-status-precedence ["capability-skipped" "capability-skipped"]) "passed"
            "multiple capability-skipped -> passed")
        (assert-eq (run-status-precedence ["failed" "capability-skipped"]) "failed"
            "failed + capability-skipped -> failed")
        (assert-eq (run-status-precedence ["blocked" "capability-skipped"]) "blocked"
            "blocked + capability-skipped -> blocked")
        (assert-eq (run-status-precedence ["missing" "capability-skipped"]) "missing"
            "missing + capability-skipped -> missing")
    ]
}

def test-unknown-fallback [] {
    test-log "\n[test-unknown-fallback]"
    [
        (assert-eq (run-status-precedence ["some-unknown-status"]) "unknown"
            "unrecognized status -> unknown")
        (assert-eq (run-status-precedence ["passed" "some-unknown-status"]) "unknown"
            "mixed with unknown -> unknown (no all-passed condition satisfied)")
    ]
}

def main [] {
    test-log "=== run/status (run-status-precedence) tests ==="
    let results = (
        (test-failed-wins-over-all)
        | append (test-running-beats-blocked-missing-passed)
        | append (test-blocked-beats-missing-passed)
        | append (test-missing-beats-passed)
        | append (test-passed-all-equal)
        | append (test-empty-list)
        | append (test-capability-skipped-transparent)
        | append (test-unknown-fallback)
    ) | flatten
    run-suite "run/status" $SUITE_PATH $results
}
