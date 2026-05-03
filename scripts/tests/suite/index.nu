# Tests for scripts/lib/suite/index.nu: record-capability-skipped-run,
# finish-suite-record, and the no-runnable / all-cap-skipped suite path.
# Run: nu scripts/tests/suite/index.nu
# Returns exit 0 on all pass, exit 1 with details on failure.

const SUITE_PATH = path self

use ../../lib/suite/index.nu [
    new-suite-id
    init-suite-record
    finish-suite-record
    record-capability-skipped-run
    record-suite-run
    compute-suite-status
]
use ../../lib/tests/assert.nu *
use ../../lib/tests/runner.nu [run-suite]

# Minimal planned cell record matching the fields used by record-capability-skipped-run.
def fixture-cap-skipped-cell [] {
    {
        cell_id: "login__opencloud-v6",
        artifact_name: "cell-login-opencloud-v6",
        flow_id: "login",
        pair: "opencloud-v6",
        execution_id: "20260101t000000-aabbccdd",
        capability_skip: {rationale: "login sender not yet implemented for opencloud v6"},
    }
}

# ----- record-capability-skipped-run: happy path run entry content -----

def test-record-capability-skipped-run-happy-path [] {
    test-log "\n[test-record-capability-skipped-run-happy-path]"
    let tmp = (^mktemp -d | str trim)
    let root = ($tmp | path join "artifacts")
    let suite_id = "20260101t120000-deadbeef"
    let cell = fixture-cap-skipped-cell
    let ts = "2026-01-01T12:00:00Z"

    with-env { OCMTS_ROOT: $tmp } {
        init-suite-record $suite_id "suite" []
        record-capability-skipped-run $suite_id $cell $ts
    }

    let record_path = ($root | path join "suites/runs" $"($suite_id).json")
    let record_exists = ($record_path | path exists)
    let suite_rec = if $record_exists { open $record_path } else { {} }
    let runs = ($suite_rec.runs? | default [])
    let entry = ($runs | where cell_id == "login__opencloud-v6" | get 0?)
    ^rm -rf $tmp
    [
        (assert-truthy $record_exists
            "suite record file written")
        (assert-truthy ($entry != null) "run entry present for cap-skipped cell")
        (assert-eq ($entry.status? | default "") "capability-skipped"
            "run entry status is capability-skipped")
        (assert-eq ($entry.exit_code? | default (-1)) 0
            "run entry exit_code is 0")
        (assert-eq ($entry.flow_id? | default "") "login"
            "run entry carries flow_id")
        (assert-eq ($entry.cell_id? | default "") "login__opencloud-v6"
            "run entry carries cell_id")
        (assert-eq ($entry.execution_id? | default "") "20260101t000000-aabbccdd"
            "run entry carries execution_id from plan")
    ]
}

# ----- finish-suite-record: capability_skipped count is persisted -----

def test-finish-suite-record-capability-skipped-count [] {
    test-log "\n[test-finish-suite-record-capability-skipped-count]"
    let tmp = (^mktemp -d | str trim)
    let suite_id = "20260101t120001-cafebabe"

    with-env { OCMTS_ROOT: $tmp } {
        init-suite-record $suite_id "suite" []
        finish-suite-record $suite_id 0 0 0 0 2
    }

    let record_path = ($tmp | path join "artifacts/suites/runs" $"($suite_id).json")
    let suite_rec = if ($record_path | path exists) { open $record_path } else { {} }
    ^rm -rf $tmp
    [
        (assert-eq ($suite_rec.capability_skipped_count? | default (-1)) 2
            "finish-suite-record: capability_skipped_count persisted as 2")
        (assert-eq ($suite_rec.passed_count? | default (-1)) 0
            "finish-suite-record: passed_count is 0")
        (assert-eq ($suite_rec.failed_count? | default (-1)) 0
            "finish-suite-record: failed_count is 0")
        (assert-eq ($suite_rec.status? | default "") "passed"
            "finish-suite-record: status is passed when failed=0 and blocked=0")
    ]
}

# ----- Suite with only cap-skipped runs gets status "passed" -----

def test-suite-all-cap-skipped-gets-passed-status [] {
    test-log "\n[test-suite-all-cap-skipped-gets-passed-status]"
    let tmp = (^mktemp -d | str trim)
    let suite_id = "20260101t120002-feedf00d"
    let cell = fixture-cap-skipped-cell
    let ts = "2026-01-01T12:00:02Z"

    with-env { OCMTS_ROOT: $tmp } {
        init-suite-record $suite_id "suite" []
        record-capability-skipped-run $suite_id $cell $ts
        finish-suite-record $suite_id 0 0 0 0 1
    }

    let record_path = ($tmp | path join "artifacts/suites/runs" $"($suite_id).json")
    let record_exists = ($record_path | path exists)
    let suite_rec = if $record_exists { open $record_path } else { {} }
    let runs = ($suite_rec.runs? | default [])
    let cap_skipped_runs = ($runs | where status == "capability-skipped")
    ^rm -rf $tmp
    [
        (assert-truthy $record_exists
            "suite record file exists")
        (assert-eq ($suite_rec.status? | default "running") "passed"
            "suite status is passed for all-cap-skipped suite")
        (assert-truthy ($suite_rec.status? != "running")
            "suite status is not running")
        (assert-eq ($suite_rec.capability_skipped_count? | default 0) 1
            "capability_skipped_count is 1")
        (assert-truthy (not ($cap_skipped_runs | is-empty))
            "runs list contains capability-skipped entries")
        (assert-eq ($cap_skipped_runs | first | get exit_code? | default (-1)) 0
            "capability-skipped run entry has exit_code 0")
    ]
}

# ----- No-runnable path regression: suite with only cap-skipped cells -----
# Simulates what cypress-suite does in the no-runnable branch:
# init -> record-capability-skipped-run -> finish-suite-record
# Verifies artifacts/suites/runs/<suite_id>.json is written with correct shape.

def test-no-runnable-suite-writes-suite-record [] {
    test-log "\n[test-no-runnable-suite-writes-suite-record]"
    let tmp = (^mktemp -d | str trim)
    let suite_id = "20260101t120003-badf00d0"
    let ts = "2026-01-01T12:00:03Z"
    let cells = [
        (fixture-cap-skipped-cell)
        {
            cell_id: "login__opencloud-v7",
            artifact_name: "cell-login-opencloud-v7",
            flow_id: "login",
            pair: "opencloud-v7",
            execution_id: "20260101t120003-11111111",
            capability_skip: {rationale: "v7 not yet implemented"},
        }
    ]

    with-env { OCMTS_ROOT: $tmp } {
        init-suite-record $suite_id "suite" []
        for cell in $cells {
            record-capability-skipped-run $suite_id $cell $ts
        }
        finish-suite-record $suite_id 0 0 0 0 ($cells | length)
    }

    let record_path = ($tmp | path join "artifacts/suites/runs" $"($suite_id).json")
    let record_exists = ($record_path | path exists)
    let suite_rec = if $record_exists { open $record_path } else { {} }
    let runs = ($suite_rec.runs? | default [])
    let cap_runs = ($runs | where status == "capability-skipped")
    ^rm -rf $tmp
    [
        (assert-truthy $record_exists
            "no-runnable: suite record file written")
        (assert-truthy (($suite_rec.status? | default "running") != "running")
            "no-runnable: status is not running after finish")
        (assert-eq ($suite_rec.status? | default "") "passed"
            "no-runnable: suite status is passed when only cap-skipped")
        (assert-eq ($suite_rec.capability_skipped_count? | default 0) 2
            "no-runnable: capability_skipped_count equals number of cap-skipped cells")
        (assert-truthy (not ($cap_runs | is-empty))
            "no-runnable: runs include capability-skipped entries")
        (assert-truthy ($cap_runs | all {|r| ($r.exit_code? | default (-1)) == 0})
            "no-runnable: all capability-skipped run entries have exit_code 0")
    ]
}

# ----- compute-suite-status baseline -----

def test-compute-suite-status [] {
    test-log "\n[test-compute-suite-status]"
    [
        (assert-eq (compute-suite-status ["passed" "passed" "passed"]) "passed"
            "compute-suite-status: all passed -> passed")
        (assert-eq (compute-suite-status ["failed"]) "failed"
            "compute-suite-status: any failed -> failed")
        (assert-eq (compute-suite-status ["passed" "passed" "blocked"]) "blocked"
            "compute-suite-status: blocked and no failed -> blocked")
        (assert-eq (compute-suite-status []) "passed"
            "compute-suite-status: no runs -> passed")
    ]
}

def main [] {
    test-log "=== Suite Index Tests ==="
    let results = (
        (test-record-capability-skipped-run-happy-path)
        | append (test-finish-suite-record-capability-skipped-count)
        | append (test-suite-all-cap-skipped-gets-passed-status)
        | append (test-no-runnable-suite-writes-suite-record)
        | append (test-compute-suite-status)
    ) | flatten
    run-suite "suite/index" $SUITE_PATH $results
}
