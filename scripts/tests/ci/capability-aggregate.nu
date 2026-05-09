# Aggregate, synthesized-result, and site-ingest fallback behavior
# for capability-skipped cells.
# Covers: aggregate summary counts, plan-aware synthesis, suite index
# reconstruction, synthesized result/run shapes, and site ingest fallback.
# Run: nu scripts/tests/ci/capability-aggregate.nu
# Returns exit 0 on all pass, exit 1 with details on failure.

const SUITE_PATH = path self

use ../../lib/ci/aggregate.nu [build-aggregate-summary reconstruct-suite-index]
use ../../lib/tests/assert.nu *
use ../../lib/tests/fixtures.nu [materialize-provenance-stubs]
use ../../lib/tests/runner.nu [run-suite]

# ---- tests ----

def test-aggregate-summary-cap-skipped [] {
    test-log "\n[test-aggregate-summary-cap-skipped]"
    let mock_manifest = {
        aggregate_status: "passed",
        results: {
            "res-1": {status: "passed"},
            "res-2": {status: "capability-skipped"},
            "res-3": {status: "capability-skipped"},
        },
    }
    let s = (build-aggregate-summary $mock_manifest)
    [
        (assert-eq $s.total 3 "total is 3")
        (assert-eq $s.passed 1 "passed is 1")
        (assert-eq $s.capability_skipped 2 "capability_skipped is 2")
        (assert-eq $s.unknown 0 "capability-skipped does not count as unknown")
        (assert-eq $s.aggregate_status "passed" "aggregate_status is passed")
    ]
}

def test-plan-aware-aggregate-synthesizes-cap-skipped [] {
    test-log "\n[test-plan-aware-aggregate-synthesizes-cap-skipped]"
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
    # "b" is cap-skipped with a full plan record; "c" is truly missing
    let cap_b = {
        cell_id: "b",
        flow_id: "login",
        pair: "opencloud-v6",
        artifact_name: "cell-login-opencloud-v6",
        scenario: "login",
        sender_platform: "opencloud",
        sender_version: "v6",
        receiver_platform: "",
        receiver_version: "",
        is_two_party: false,
        execution_id: "20260101t000000-aabbccdd",
        capability_skip: {rationale: "login sender not yet implemented"},
    }
    let manifest = (aggregate-suite-manifests-plan-aware
        [$cell_a_dir] "suite-test" ["a" "b" "c"]
        --capability-skipped-cells [$cap_b])
    let summary = (build-aggregate-summary $manifest)
    ^rm -rf $tmp
    let all_results = ($manifest.results | transpose k v | each {|r| $r.v})
    let b_result = ($all_results | where cell_id == "b" | get 0?)
    let c_result = ($all_results | where cell_id == "c" | get 0?)
    let b_cell = ($manifest.cells | get --optional "b")
    let b_run = ($manifest.runs | get --optional "20260101t000000-aabbccdd")
    [
        (assert-eq $summary.passed 1 "plan-aware: 1 passed")
        (assert-eq $summary.capability_skipped 1 "plan-aware: 1 capability-skipped synthesized")
        (assert-eq $summary.missing 1 "plan-aware: 1 truly missing")
        (assert-eq ($b_result.status? | default "") "capability-skipped"
            "plan-aware: cell b synthesized as capability-skipped")
        (assert-eq ($b_result.exit_code? | default (-1)) 0
            "plan-aware: capability-skipped result exit_code 0")
        (assert-eq ($b_result.execution_id? | default "") "20260101t000000-aabbccdd"
            "plan-aware: capability-skipped result carries actual execution_id")
        (assert-eq ($b_result.failure_reason? | default "") "login sender not yet implemented"
            "plan-aware: failure_reason set from capability_skip.rationale")
        (assert-eq ($c_result.status? | default "") "missing"
            "plan-aware: cell c synthesized as missing")
        (assert-eq $manifest.aggregate_status "missing"
            "plan-aware: aggregate_status is missing when a truly-missing cell exists")
        (assert-truthy ($b_cell != null) "plan-aware: cells map entry synthesized for cap-skipped cell")
        (assert-eq ($b_cell.id? | default "") "b"
            "plan-aware: synthesized cell id field matches map key")
        (assert-eq ($b_cell.flow_id? | default "") "login"
            "plan-aware: synthesized cell carries flow_id from plan")
        (assert-eq ($b_cell.pair? | default "") "opencloud-v6"
            "plan-aware: synthesized cell carries pair from plan")
        (assert-eq ($b_cell.artifact_name? | default "") "cell-login-opencloud-v6"
            "plan-aware: synthesized cell carries artifact_name from plan")
        (assert-eq ($b_cell.scenario? | default "") "login"
            "plan-aware: synthesized cell carries scenario from plan")
        (assert-eq ($b_cell.is_two_party? | default true) false
            "plan-aware: synthesized cell carries is_two_party from plan")
        (assert-truthy ("login" in ($manifest.flows | columns))
            "plan-aware: flows entry synthesized for new flow_id")
        (assert-truthy ($b_run != null) "plan-aware: run synthesized for cap-skipped cell with execution_id")
        (assert-eq ($b_run.cell_id? | default "") "b"
            "plan-aware: synthesized run cell_id matches cell key")
        (assert-eq ($b_run.status? | default "") "capability-skipped"
            "plan-aware: synthesized run status is capability-skipped")
    ]
}

def test-reconstruct-suite-index-cap-skipped [] {
    test-log "\n[test-reconstruct-suite-index-cap-skipped]"
    let tmp = (^mktemp -d | str trim)
    let artifacts_root = ($tmp | path join "artifacts")
    let ts = "2026-01-01T00:00:00Z"
    let suite_id = "20260101t000000-aabbccdd"

    let manifest = {
        schema_version: 1,
        generated_at: $ts,
        suite_id: $suite_id,
        producer: {name: "ocmts-aggregator", version: "0.1.0"},
        flows: {login: {id: "login", description: "OCM login flow"}},
        cells: {
            "cell-passed": {
                id: "cell-passed",
                flow_id: "login",
                pair: "nextcloud-v34",
                artifact_name: "cell-login-nextcloud-v34",
            }
            "cell-cap-skipped": {
                id: "cell-cap-skipped",
                flow_id: "login",
                pair: "opencloud-v6",
                artifact_name: "cell-login-opencloud-v6",
            }
        },
        runs: {},
        results: {
            "result-passed": {
                schema_version: 1,
                id: "result-passed",
                run_id: "",
                execution_id: "",
                cell_id: "cell-passed",
                exit_code: 0,
                status: "passed",
                finished_at: $ts,
                failure_reason: "",
            }
            "result-cap-skipped": {
                schema_version: 1,
                id: "result-cap-skipped",
                run_id: "",
                execution_id: "",
                cell_id: "cell-cap-skipped",
                exit_code: 0,
                status: "capability-skipped",
                finished_at: $ts,
                failure_reason: "",
            }
        },
        indexes: {latest_terminal_result_by_cell: {}},
        aggregate_status: "passed",
    }

    let record_path = (reconstruct-suite-index $manifest $artifacts_root)
    let suite_record = if ($record_path != null) and ($record_path | path exists) {
        open $record_path
    } else {
        {}
    }
    let run_statuses = ($suite_record.runs? | default [] | each {|r| $r.status})
    ^rm -rf $tmp
    [
        (assert-truthy ($record_path != null)
            "reconstruct: returns non-null for valid suite_id")
        (assert-eq ($suite_record.status? | default "") "passed"
            "reconstruct: suite status is passed")
        (assert-eq ($suite_record.passed_count? | default (-1)) 1
            "reconstruct: passed_count is 1")
        (assert-eq ($suite_record.capability_skipped_count? | default (-1)) 1
            "reconstruct: capability_skipped_count is 1")
        (assert-eq ($suite_record.blocked_count? | default (-1)) 0
            "reconstruct: blocked_count is 0 (capability-skipped not counted as blocked)")
        (assert-truthy ("capability-skipped" in $run_statuses)
            "reconstruct: run entry with capability-skipped status present")
    ]
}

def test-synthesized-result-no-lifecycle-status [] {
    test-log "\n[test-synthesized-result-no-lifecycle-status]"
    use ../../lib/ci/aggregate.nu [aggregate-suite-manifests-plan-aware]
    let cap_b = {
        cell_id: "b",
        flow_id: "login",
        pair: "opencloud-v6",
        artifact_name: "cell-login-opencloud-v6",
        scenario: "login",
        sender_platform: "opencloud",
        sender_version: "v6",
        receiver_platform: "",
        receiver_version: "",
        is_two_party: false,
        execution_id: "20260101t000000-aabbccdd",
        capability_skip: {rationale: "not implemented"},
    }
    # No artifact dirs: both cells synthesized (b = cap-skipped, c = missing).
    let manifest = (aggregate-suite-manifests-plan-aware
        [] "suite-test" ["b" "c"]
        --capability-skipped-cells [$cap_b])
    let b_result = ($manifest.results | get "result-capability-skipped-b")
    let c_result = ($manifest.results | get "result-missing-c")
    [
        (assert-truthy (not ("lifecycle_status" in ($b_result | columns)))
            "cap-skipped synthesized result must NOT carry lifecycle_status")
        (assert-truthy (not ("lifecycle_status" in ($c_result | columns)))
            "missing synthesized result must NOT carry lifecycle_status")
        (assert-eq ($b_result.schema_version? | default 0) 1
            "cap-skipped result schema_version is 1")
        (assert-eq ($c_result.schema_version? | default 0) 1
            "missing result schema_version is 1")
    ]
}

def test-synthesized-run-lifecycle-status-completed [] {
    test-log "\n[test-synthesized-run-lifecycle-status-completed]"
    use ../../lib/ci/aggregate.nu [aggregate-suite-manifests-plan-aware]
    let cap_b = {
        cell_id: "b",
        flow_id: "login",
        pair: "opencloud-v6",
        artifact_name: "cell-login-opencloud-v6",
        scenario: "login",
        sender_platform: "opencloud",
        sender_version: "v6",
        receiver_platform: "",
        receiver_version: "",
        is_two_party: false,
        execution_id: "20260101t000000-aabbccdd",
        capability_skip: {rationale: "not implemented"},
    }
    let manifest = (aggregate-suite-manifests-plan-aware
        [] "suite-test" ["b"]
        --capability-skipped-cells [$cap_b])
    let b_run = ($manifest.runs | get --optional "20260101t000000-aabbccdd")
    [
        (assert-truthy ($b_run != null)
            "synthesized run exists for cap-skipped cell with execution_id")
        (assert-eq ($b_run.lifecycle_status? | default "") "completed"
            "synthesized RUN lifecycle_status must be 'completed', not 'capability-skipped'")
        (assert-eq ($b_run.status? | default "") "capability-skipped"
            "synthesized RUN status field stays 'capability-skipped'")
    ]
}

def test-aggregate-result-shape-via-build-result-v1 [] {
    test-log "\n[test-aggregate-result-shape-via-build-result-v1]"
    use ../../lib/ci/aggregate.nu [aggregate-suite-manifests-plan-aware]
    use ../../lib/run/result-envelope.nu [build-result-v1]
    let cap_b = {
        cell_id: "b",
        flow_id: "login",
        pair: "opencloud-v6",
        artifact_name: "cell-login-opencloud-v6",
        scenario: "login",
        sender_platform: "opencloud",
        sender_version: "v6",
        receiver_platform: "",
        receiver_version: "",
        is_two_party: false,
        execution_id: "20260101t000000-aabbccdd",
        capability_skip: {rationale: "not implemented"},
    }
    let manifest = (aggregate-suite-manifests-plan-aware
        [] "suite-test" ["b" "c"]
        --capability-skipped-cells [$cap_b])
    let b_result = ($manifest.results | get "result-capability-skipped-b")
    let c_result = ($manifest.results | get "result-missing-c")
    # Required fields from build-result-v1 schema must be present.
    let required = ["schema_version" "id" "run_id" "execution_id" "cell_id" "status" "exit_code"]
    let b_cols = ($b_result | columns)
    let c_cols = ($c_result | columns)
    [
        (assert-truthy (not ("lifecycle_status" in $b_cols))
            "cap-skipped result: lifecycle_status absent (build-result-v1 SSOT)")
        (assert-truthy (not ("lifecycle_status" in $c_cols))
            "missing result: lifecycle_status absent (build-result-v1 SSOT)")
        (assert-truthy (($required | all {|f| $f in $b_cols}))
            "cap-skipped result has all required build-result-v1 fields")
        (assert-truthy (($required | all {|f| $f in $c_cols}))
            "missing result has all required build-result-v1 fields")
        (assert-eq ($b_result.status? | default "") "capability-skipped"
            "cap-skipped result status preserved via build-result-v1")
        (assert-eq ($c_result.status? | default "") "missing"
            "missing result status preserved via build-result-v1")
        (assert-truthy (not ("attempt_number" in $b_cols))
            "attempt_number is absent from result (not in build-result-v1 schema)")
    ]
}

def test-site-ingest-cap-skipped-fallback-non-empty-exec-id [] {
    test-log "\n[test-site-ingest-cap-skipped-fallback-non-empty-exec-id]"
    use ../../lib/site/ingest.nu [ingest-site]
    let tmp = (^mktemp -d | str trim)
    materialize-provenance-stubs $tmp
    let artifacts_root = ($tmp | path join "artifacts")
    let public_dir = ($tmp | path join "public")
    let ts = "2026-01-01T00:00:00Z"
    let suite_id = "20260101t000000-aabbccff"
    let rules = {scenarios: {}}

    # Write suite index with a cap-skipped run that has a non-empty execution_id
    # but NO manifest file on disk - this is the I3 scenario.
    let suites_dir = ($artifacts_root | path join "suites")
    let runs_dir = ($suites_dir | path join "runs")
    mkdir $runs_dir
    let suite_record = {
        schema_version: 2,
        suite_id: $suite_id,
        suite_kind: "aggregated",
        started_at: $ts, finished_at: $ts,
        status: "passed",
        scheduled_cells: ["cell-cap-skipped"],
        runs: [
            {
                flow_id: "login",
                pair: "opencloud-v6",
                execution_id: "20260101t000000-skipexec",
                cell_id: "cell-cap-skipped",
                artifact_name: "cell-login-opencloud-v6",
                status: "capability-skipped",
                exit_code: 0,
                started_at: $ts,
                finished_at: $ts,
            }
        ],
        passed_count: 0, failed_count: 0, blocked_count: 0,
        capability_skipped_count: 1,
    }
    $suite_record | to json --indent 2 | save --force ($runs_dir | path join $"($suite_id).json")
    $suite_id | save --force ($suites_dir | path join "LATEST_SUITE_ID")
    # Deliberately do NOT create the manifest file at:
    # artifacts/login/opencloud-v6/20260101t000000-skipexec/meta/suite-manifest.v1.json

    ingest-site $artifacts_root $rules $tmp $public_dir --latest-suite

    let site_manifest_path = ($public_dir | path join "suite-manifest.v1.json")
    let site_manifest_exists = ($site_manifest_path | path exists)
    let site_manifest = if $site_manifest_exists { open $site_manifest_path } else { {} }
    let all_results = ($site_manifest.results? | default {} | transpose k v | each {|r| $r.v})
    let cap_results = ($all_results | where {|r| ($r.status? | default "") == "capability-skipped"})
    ^rm -rf $tmp
    [
        (assert-truthy $site_manifest_exists
            "ingest-site writes suite-manifest.v1.json")
        (assert-eq ($cap_results | length) 1
            "site-ingest B3 fallback fires for non-empty exec_id when manifest missing")
        (assert-truthy (not ($cap_results | is-empty))
            "synthesized capability-skipped result present in site manifest")
        (assert-truthy (not ("lifecycle_status" in (($cap_results | first) | columns)))
            "synthesized site-ingest cap-skipped result has no lifecycle_status")
    ]
}

def main [] {
    test-log "=== CI Capability Aggregate Tests ==="
    let results = (
        (test-aggregate-summary-cap-skipped)
        | append (test-plan-aware-aggregate-synthesizes-cap-skipped)
        | append (test-reconstruct-suite-index-cap-skipped)
        | append (test-synthesized-result-no-lifecycle-status)
        | append (test-synthesized-run-lifecycle-status-completed)
        | append (test-aggregate-result-shape-via-build-result-v1)
        | append (test-site-ingest-cap-skipped-fallback-non-empty-exec-id)
    ) | flatten
    run-suite "ci/capability-aggregate" $SUITE_PATH $results
}
