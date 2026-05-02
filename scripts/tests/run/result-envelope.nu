# Unit tests for scripts/lib/run/result-envelope.nu.
# Run: nu scripts/tests/run/result-envelope.nu

const SUITE_PATH = path self

use ../../lib/run/result-envelope.nu [build-result-v1]
use ../../lib/tests/assert.nu *
use ../../lib/tests/runner.nu [run-suite]

def minimal-fields [] {
    {
        id: "result-abc123",
        run_id: "abc123",
        execution_id: "abc123",
        cell_id: "cell-foo",
        status: "passed",
        exit_code: 0,
    }
}

def test-build-minimal [] {
    test-log "\n[test-build-minimal]"
    let r = (build-result-v1 (minimal-fields))
    [
        (assert-eq $r.schema_version 1 "schema_version is 1")
        (assert-eq $r.status "passed" "status is passed")
        (assert-eq $r.exit_code 0 "exit_code is 0")
        (assert-eq ($r.failure_reason? | default null) null "failure_reason absent")
        (assert-eq ($r.verdict? | default null) null "verdict absent")
    ]
}

def test-build-with-optional-fields [] {
    test-log "\n[test-build-with-optional-fields]"
    let r = (build-result-v1 ((minimal-fields) | merge {
        failure_reason: "some failure"
        warnings: ["w1"]
        evidence: [{kind: "log" path: "docker/logs/x.log"}]
        capability_skip: {rationale: "not implemented"}
    }))
    [
        (assert-eq $r.failure_reason "some failure" "failure_reason present")
        (assert-eq ($r.warnings | length) 1 "warnings has 1 entry")
        (assert-eq ($r.evidence | length) 1 "evidence has 1 entry")
        (assert-eq $r.capability_skip.rationale "not implemented" "capability_skip present")
    ]
}

def test-build-empty-failure-reason-omitted [] {
    test-log "\n[test-build-empty-failure-reason-omitted]"
    let r = (build-result-v1 ((minimal-fields) | merge {failure_reason: ""}))
    [
        (assert-eq ($r.failure_reason? | default null) null "empty failure_reason omitted")
    ]
}

def test-build-missing-required-errors [] {
    test-log "\n[test-build-missing-required-errors]"
    let r1 = (try { build-result-v1 {run_id: "x" execution_id: "x" cell_id: "x" status: "passed" exit_code: 0}; "no-error" } catch { "error" })
    let r2 = (try { build-result-v1 {id: "x" execution_id: "x" cell_id: "x" status: "passed" exit_code: 0}; "no-error" } catch { "error" })
    [
        (assert-eq $r1 "error" "missing id errors")
        (assert-eq $r2 "error" "missing run_id errors")
    ]
}

def test-build-invalid-status-errors [] {
    test-log "\n[test-build-invalid-status-errors]"
    let r = (try { build-result-v1 ((minimal-fields) | merge {status: "not-a-status"}); "no-error" } catch { "error" })
    [
        (assert-eq $r "error" "invalid status errors")
    ]
}

def test-build-capability-skipped [] {
    test-log "\n[test-build-capability-skipped]"
    let r = (build-result-v1 ((minimal-fields) | merge {status: "capability-skipped" exit_code: 0}))
    [
        (assert-eq $r.status "capability-skipped" "capability-skipped status accepted")
        (assert-eq $r.schema_version 1 "schema_version is 1 for cap-skipped")
    ]
}

def test-build-suite-id-omitted-when-empty [] {
    test-log "\n[test-build-suite-id-omitted-when-empty]"
    let r = (build-result-v1 ((minimal-fields) | merge {suite_id: "" suite_kind: ""}))
    [
        (assert-eq ($r.suite_id? | default null) null "empty suite_id omitted")
        (assert-eq ($r.suite_kind? | default null) null "empty suite_kind omitted")
    ]
}

def main [] {
    test-log "=== run/result-envelope tests ==="
    let results = (
        (test-build-minimal)
        | append (test-build-with-optional-fields)
        | append (test-build-empty-failure-reason-omitted)
        | append (test-build-missing-required-errors)
        | append (test-build-invalid-status-errors)
        | append (test-build-capability-skipped)
        | append (test-build-suite-id-omitted-when-empty)
    ) | flatten
    run-suite "run/result-envelope" $SUITE_PATH $results
}
