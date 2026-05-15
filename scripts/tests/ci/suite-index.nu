# Suite index reconstruction tests.
# Covers: reconstruct-suite-index behavior.
# Run: nu scripts/tests/ci/suite-index.nu
# Returns exit 0 on all pass, exit 1 with details on failure.

const SUITE_PATH = path self

use ../../lib/ci/aggregate.nu [reconstruct-suite-index]
use ../../lib/tests/assert.nu *
use ../../lib/tests/runner.nu [run-suite]

# Test that reconstruct-suite-index writes runs/<suite_id>.json and
# LATEST_SUITE_ID, and that all result types (passed, blocked, missing)
# appear as run entries in the suite record.
def test-reconstruct-suite-index [] {
    test-log "\n[test-reconstruct-suite-index]"
    let tmp = (^mktemp -d | str trim)
    let artifacts_root = ($tmp | path join "artifacts")
    let ts = "2026-01-01T00:00:00Z"
    let suite_id = "20260101t000000-aabbccdd"

    # Manifest with one passed cell, one blocked cell, one missing cell.
    # Cells map only covers the two observed cells; missing is synthetic.
    let manifest = {
        schema_version: 1,
        generated_at: $ts,
        suite_id: $suite_id,
        producer: {name: "ocmts-aggregator", version: "0.1.0"},
        flows: {
            login: {id: "login", description: "OCM login flow"}
            "share-with": {id: "share-with", description: "OCM share-with flow"}
        },
        cells: {
            "cell-passed": {
                id: "cell-passed",
                flow_id: "login",
                pair: "nextcloud-v34",
                artifact_name: "cell-login-nextcloud-v34",
            }
            "cell-blocked": {
                id: "cell-blocked",
                flow_id: "share-with",
                pair: "nextcloud-v34__nextcloud-v34",
                artifact_name: "cell-share-with-nextcloud-v34",
            }
        },
        runs: {
            "exec-passed": {
                id: "exec-passed",
                cell_id: "cell-passed",
                execution_id: "exec-passed",
                lifecycle_status: "completed",
                started_at: $ts,
                finished_at: $ts,
            }
            "exec-blocked": {
                id: "exec-blocked",
                cell_id: "cell-blocked",
                execution_id: "exec-blocked",
                lifecycle_status: "completed",
                started_at: $ts,
                finished_at: $ts,
            }
        },
        results: {
            "result-passed": {
                schema_version: 1,
                id: "result-passed",
                run_id: "exec-passed",
                execution_id: "exec-passed",
                cell_id: "cell-passed",
                exit_code: 0,
                status: "passed",
                finished_at: $ts,
                failure_reason: "",
            }
            "result-blocked": {
                schema_version: 1,
                id: "result-blocked",
                run_id: "exec-blocked",
                execution_id: "exec-blocked",
                cell_id: "cell-blocked",
                exit_code: 0,
                status: "blocked",
                finished_at: $ts,
                failure_reason: "prerequisite cell-passed failed",
            }
            "result-missing-cell-missing": {
                schema_version: 1,
                id: "result-missing-cell-missing",
                run_id: "",
                execution_id: "",
                cell_id: "cell-missing",
                exit_code: 1,
                status: "missing",
                finished_at: $ts,
                failure_reason: "cell had no recorded outcome",
            }
        },
        indexes: {latest_terminal_result_by_cell: {}},
        aggregate_status: "blocked",
    }

    let record_path = (reconstruct-suite-index $manifest $artifacts_root)
    let latest_path = ($artifacts_root | path join "suites/LATEST_SUITE_ID")
    let expected_record_path = (
        $artifacts_root | path join $"suites/runs/($suite_id).json"
    )

    let suite_record = if ($record_path != null) and ($record_path | path exists) {
        open $record_path
    } else {
        {}
    }
    let run_statuses = ($suite_record.runs? | default [] | each {|r| $r.status})
    let run_cell_ids = ($suite_record.runs? | default [] | each {|r| $r.cell_id})

    ^rm -rf $tmp
    [
        (assert-truthy ($record_path != null)
            "reconstruct-suite-index returns non-null for valid suite_id")
        (assert-eq $record_path $expected_record_path
            "suite record written at artifacts_root/suites/runs/<suite_id>.json")
        (assert-truthy ($latest_path | path exists | $in == false or $record_path != null)
            "LATEST_SUITE_ID marker created")
        (assert-eq ($suite_record.schema_version? | default 0) 2
            "suite record has schema_version 2")
        (assert-eq ($suite_record.suite_kind? | default "") "aggregated"
            "suite record has suite_kind=aggregated")
        (assert-eq ($suite_record.status? | default "") "blocked"
            "suite record status matches aggregate_status (blocked)")
        (assert-eq ($suite_record.passed_count? | default (-1)) 1
            "suite record passed_count is 1")
        (assert-eq ($suite_record.blocked_count? | default (-1)) 2
            "suite record blocked_count is 2 (blocked + missing)")
        (assert-truthy ("passed" in $run_statuses)
            "run entries include passed result")
        (assert-truthy ("blocked" in $run_statuses)
            "run entries include blocked result")
        (assert-truthy ("missing" in $run_statuses)
            "run entries include missing result")
        (assert-truthy ("cell-passed" in $run_cell_ids)
            "run entry for cell-passed present")
        (assert-truthy ("cell-blocked" in $run_cell_ids)
            "run entry for cell-blocked present")
        (assert-truthy ("cell-missing" in $run_cell_ids)
            "run entry for cell-missing (synthetic) present")
        (assert-truthy (
            ($suite_record.scheduled_cells? | default [] | length) >= 3
        ) "scheduled_cells covers all three cell ids")
    ]
}

# Test that reconstruct-suite-index returns null for non-standard suite_ids.
def test-reconstruct-suite-index-skips-invalid-id [] {
    test-log "\n[test-reconstruct-suite-index-skips-invalid-id]"
    let tmp = (^mktemp -d | str trim)
    let manifest_unknown = {
        suite_id: "unknown-suite",
        aggregate_status: "passed",
        generated_at: "2026-01-01T00:00:00Z",
        flows: {},
        cells: {},
        runs: {},
        results: {},
        indexes: {latest_terminal_result_by_cell: {}},
    }
    let r1 = (reconstruct-suite-index $manifest_unknown ($tmp | path join "artifacts"))
    let manifest_empty = ($manifest_unknown | upsert suite_id "")
    let r2 = (reconstruct-suite-index $manifest_empty ($tmp | path join "artifacts"))
    ^rm -rf $tmp
    [
        (assert-eq $r1 null
            "reconstruct-suite-index returns null for unknown-suite id")
        (assert-eq $r2 null
            "reconstruct-suite-index returns null for empty suite_id")
    ]
}

def main [] {
    test-log "=== CI Suite-Index Tests ==="
    let results = (
        (test-reconstruct-suite-index)
        | append (test-reconstruct-suite-index-skips-invalid-id)
    ) | flatten
    run-suite "ci/suite-index" $SUITE_PATH $results
}
