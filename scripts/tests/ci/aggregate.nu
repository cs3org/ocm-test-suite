# Aggregate tests.
# Covers: build-aggregate-summary, aggregate-suite-manifests-plan-aware,
# aggregate workflow bridge, needs/archive checks.
# Run: nu scripts/tests/ci/aggregate.nu
# Returns exit 0 on all pass, exit 1 with details on failure.

const SUITE_PATH = path self

use ../../lib/ci/planner.nu [plan-suite]
use ../../lib/ci/aggregate.nu [build-aggregate-summary]
use ../../lib/ci/workflow-gen.nu [build-ci-matrix-yml build-aggregate-needs-block]
use ../../lib/tests/assert.nu *
use ../../lib/tests/runner.nu [run-suite]
use ./fixtures.nu [fixture-rules fixture-prereqs fixture-flow-caps prod-plan]

# ---- tests ----

def test-aggregate-summary-counts [] {
    test-log "\n[test-aggregate-summary-counts]"
    let mock_manifest = {
        aggregate_status: "failed",
        results: {
            "res-1": {status: "passed"},
            "res-2": {status: "failed"},
            "res-3": {status: "blocked"},
            "res-4": {status: "infra-failed"},
            "res-5": {status: "passed"},
            "res-6": {status: "cleanup-failed"},
        },
    }
    let s = (build-aggregate-summary $mock_manifest)
    [
        (assert-eq $s.total 6 "total count is 6")
        (assert-eq $s.passed 2 "passed count is 2")
        (assert-eq $s.failed 1 "failed count is 1")
        (assert-eq $s.infra_failed 1 "infra_failed count is 1")
        (assert-eq $s.cleanup_failed 1 "cleanup_failed count is 1")
        (assert-eq $s.blocked 1 "blocked count is 1")
        (assert-eq $s.unknown 0 "unknown count is 0")
        (assert-eq $s.aggregate_status "failed" "aggregate_status is failed")
    ]
}

def test-aggregate-summary-empty [] {
    test-log "\n[test-aggregate-summary-empty]"
    let mock_manifest = {
        aggregate_status: "passed",
        results: {},
    }
    let s = (build-aggregate-summary $mock_manifest)
    [
        (assert-eq $s.total 0 "empty results: total is 0")
        (assert-eq $s.passed 0 "empty results: passed is 0")
        (assert-eq $s.aggregate_status "passed" "aggregate_status is passed")
    ]
}

def test-aggregate-upload-step [] {
    test-log "\n[test-aggregate-upload-step]"
    let rules = fixture-rules
    let prereqs = fixture-prereqs
    let plan = (plan-suite $rules $prereqs (fixture-flow-caps) {})
    let yml = (build-ci-matrix-yml $plan)
    [
        (assert-truthy ($yml | str contains "Upload aggregate outputs")
            "aggregate job has Upload aggregate outputs step")
        (assert-truthy ($yml | str contains "name: aggregate-summary")
            "aggregate upload uses artifact name aggregate-summary")
        (assert-truthy ($yml | str contains "path: artifacts/suites/aggregated/")
            "aggregate upload path is artifacts/suites/aggregated/")
    ]
}

def test-aggregate-cap-skipped-passthrough [] {
    test-log "\n[test-aggregate-cap-skipped-passthrough]"
    let rules = fixture-rules
    let prereqs = fixture-prereqs
    let plan = (plan-suite $rules $prereqs (fixture-flow-caps) {})
    let yml = (build-ci-matrix-yml $plan)
    [
        (assert-truthy ($yml | str contains "--capability-skipped-json artifacts/capability-skipped-cells.json")
            "aggregate step uses ci plan --capability-skipped-json to write cap-skipped cells")
        (assert-truthy (not ($yml | str contains "jq"))
            "aggregate step has no inline jq usage")
        (assert-truthy ($yml | str contains "--capability-skipped-cells artifacts/capability-skipped-cells.json")
            "aggregate step passes the capability-skipped JSON file path")
        (assert-truthy ($yml | str contains "find-suite-dirs artifacts")
            "aggregate step uses ci find-suite-dirs to collect suite dirs")
        (assert-truthy ($yml | str contains "--dirs-file artifacts/suite-dirs.txt")
            "aggregate step passes suite dirs via --dirs-file")
    ]
}

def test-aggregate-needs-block-format [] {
    test-log "\n[test-aggregate-needs-block-format]"
    let block = (build-aggregate-needs-block ["login_nextcloud_v34" "share_with_nextcloud_v34_nextcloud_v34"])
    [
        (assert-truthy ($block | str contains "needs:")
            "aggregate needs block contains 'needs:'")
        (assert-truthy ($block | str contains "setup,")
            "aggregate needs block contains 'setup,'")
        (assert-truthy ($block | str contains "login_nextcloud_v34,")
            "aggregate needs block contains login job")
        (assert-truthy ($block | str contains "share_with_nextcloud_v34_nextcloud_v34,")
            "aggregate needs block contains share-with job")
    ]
}

def test-wave-plan-aware-aggregate [] {
    test-log "\n[test-wave-plan-aware-aggregate]"
    use ../../lib/ci/aggregate.nu [build-aggregate-summary aggregate-status]
    # Simulate a manifest with one passed and two missing cells.
    let mock_manifest = {
        aggregate_status: "missing",
        results: {
            "res-a": {status: "passed", cell_id: "a"},
            "res-b": {status: "missing", cell_id: "b"},
            "res-c": {status: "missing", cell_id: "c"},
        },
    }
    let summary = (build-aggregate-summary $mock_manifest)
    [
        (assert-eq $summary.total 3 "plan-aware summary: total 3")
        (assert-eq $summary.passed 1 "plan-aware summary: 1 passed")
        (assert-eq $summary.missing 2 "plan-aware summary: 2 missing")
        (assert-eq $summary.aggregate_status "missing" "aggregate_status is missing when cells are missing but none failed")
    ]
}

def test-plan-aware-aggregate-injects-missing [] {
    test-log "\n[test-plan-aware-aggregate-injects-missing]"
    use ../../lib/ci/aggregate.nu [aggregate-suite-manifests-plan-aware build-aggregate-summary]
    let tmp = (^mktemp -d | str trim)
    let cell_a_dir = ($tmp | path join "cell-a")
    mkdir ($cell_a_dir | path join "meta")
    let ts = "2026-01-01T00:00:00Z"
    let manifest_a = {
        schema_version: 1,
        generated_at: $ts,
        suite_id: "suite-test",
        producer: {name: "ocmts-cell", version: "0.1.0"},
        flows: {},
        cells: {},
        runs: {},
        results: {
            "result-a": {
                schema_version: 1,
                id: "result-a",
                run_id: "",
                execution_id: "",
                cell_id: "a",
                exit_code: 0,
                status: "passed",
                finished_at: $ts,
                failure_reason: "",
            }
        },
        indexes: {latest_terminal_result_by_cell: {}},
    }
    $manifest_a | to json --indent 2 | save ($cell_a_dir | path join "meta/suite-manifest.v1.json")
    let manifest = (aggregate-suite-manifests-plan-aware [$cell_a_dir] "suite-test" ["a" "b" "c"])
    let summary = (build-aggregate-summary $manifest)
    ^rm -rf $tmp
    let all_results = ($manifest.results | transpose k v | each {|r| $r.v})
    let b_missing = ($all_results | where cell_id == "b" | where status == "missing" | is-not-empty)
    let c_missing = ($all_results | where cell_id == "c" | where status == "missing" | is-not-empty)
    [
        (assert-eq $summary.passed 1 "plan-aware agg: 1 passed cell")
        (assert-eq $summary.missing 2 "plan-aware agg: 2 missing cells injected")
        (assert-eq $manifest.aggregate_status "missing" "plan-aware agg: aggregate_status is missing")
        (assert-truthy $b_missing "plan-aware agg: cell b injected as missing")
        (assert-truthy $c_missing "plan-aware agg: cell c injected as missing")
    ]
}

def test-aggregate-needs-flow-jobs [] {
    test-log "\n[test-aggregate-needs-flow-jobs]"
    let rules = fixture-rules
    let prereqs = fixture-prereqs
    let plan = (plan-suite $rules $prereqs (fixture-flow-caps) {})
    let yml = (build-ci-matrix-yml $plan)
    [
        (assert-truthy ($yml | str contains "login,")
            "aggregate needs block contains login flow job")
        (assert-truthy ($yml | str contains "share-with,")
            "aggregate needs block contains share-with flow job")
        (assert-truthy (not ($yml | str contains "wave_0,"))
            "aggregate needs block does not reference wave_0")
        (assert-truthy (not ($yml | str contains "wave_1,"))
            "aggregate needs block does not reference wave_1")
    ]
}

def test-aggregate-archive-flag-present [] {
    test-log "\n[test-aggregate-archive-flag-present]"
    let rules = fixture-rules
    let prereqs = fixture-prereqs
    let plan = (plan-suite $rules $prereqs (fixture-flow-caps) {})
    let yml = (build-ci-matrix-yml $plan)
    [
        (assert-truthy ($yml | str contains "--archive")
            "generated aggregate command includes --archive flag")
    ]
}

def test-aggregate-needs-includes-webapp-share [] {
    test-log "\n[test-aggregate-needs-includes-webapp-share]"
    let yml = (build-ci-matrix-yml (prod-plan).plan)
    [
        (assert-truthy ($yml | str contains "webapp-share,")
            "aggregate needs block contains webapp-share flow job")
    ]
}

def main [] {
    test-log "=== CI Aggregate Tests ==="
    let results = (
        (test-aggregate-summary-counts)
        | append (test-aggregate-summary-empty)
        | append (test-aggregate-upload-step)
        | append (test-aggregate-cap-skipped-passthrough)
        | append (test-aggregate-needs-block-format)
        | append (test-wave-plan-aware-aggregate)
        | append (test-plan-aware-aggregate-injects-missing)
        | append (test-aggregate-needs-flow-jobs)
        | append (test-aggregate-archive-flag-present)
        | append (test-aggregate-needs-includes-webapp-share)
    ) | flatten
    run-suite "ci/aggregate" $SUITE_PATH $results
}
