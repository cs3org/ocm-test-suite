# Site ingest tests.
# Covers: ingest-site missing-injection and cell-list fallback behavior.
# Run: nu scripts/tests/ci/site-ingest.nu
# Returns exit 0 on all pass, exit 1 with details on failure.

const SUITE_PATH = path self

use ../../lib/tests/assert.nu *
use ../../lib/tests/fixtures.nu [materialize-provenance-stubs]
use ./fixtures.nu [patch-flow-glyph-ids]
use ../../lib/tests/runner.nu [run-suite]

def test-ingest-missing-injection [] {
    test-log "\n[test-ingest-missing-injection]"
    use ../../lib/site/ingest.nu [ingest-site]
    let tmp = (^mktemp -d | str trim)
    materialize-provenance-stubs $tmp
    patch-flow-glyph-ids $tmp
    let artifacts_root = ($tmp | path join "artifacts")
    let public_dir = ($tmp | path join "public")
    let ts = "2026-01-01T00:00:00Z"
    let suite_id = "20260101t000000-aabbccdd"

    # Inline matrix rules record with no matrix entries (ingest from suite only).
    let rules = {matrix: {}}

    # Write a fake per-run manifest for cell-a (passed).
    let run_dir = ($artifacts_root | path join "login" "nextcloud-v34" "exec-aaa")
    mkdir ($run_dir | path join "meta")
    let run_manifest = {
        schema_version: 1,
        generated_at: $ts,
        execution_context: {},
        flows: {login: {id: "login"}},
        cells: {"cell-a": {id: "cell-a", flow_id: "login", pair: "nextcloud-v34", artifact_name: "cell-login-nc-v34"}},
        runs: {"exec-aaa": {id: "exec-aaa", cell_id: "cell-a", started_at: $ts, finished_at: $ts}},
        results: {
            "result-a": {
                schema_version: 1, id: "result-a", run_id: "exec-aaa",
                execution_id: "exec-aaa", cell_id: "cell-a",
                exit_code: 0, status: "passed", finished_at: $ts, failure_reason: "",
                evidence: [],
            }
        },
        indexes: {latest_terminal_result_by_cell: {}},
    }
    $run_manifest | to json --indent 2 | save --force ($run_dir | path join "meta/suite-manifest.v1.json")
    mkdir ($run_dir | path join "compose")
    {
        images: {sender: "ghcr.io/example/sender:tag"},
    } | to json --indent 2 | save --force ($run_dir | path join "meta/run.json")
    {
        schema_version: 1,
        stack_def_sha256: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
        stack_env_sha256: "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
    } | to json --indent 2 | save --force ($run_dir | path join "compose/manifest.v1.json")

    # Write suite index so --latest-suite mode resolves correctly.
    let suites_dir = ($artifacts_root | path join "suites")
    let runs_dir = ($suites_dir | path join "runs")
    mkdir $runs_dir
    let suite_record = {
        schema_version: 2,
        suite_id: $suite_id,
        suite_kind: "aggregated",
        started_at: $ts, finished_at: $ts,
        status: "missing",
        scheduled_cells: ["cell-a" "cell-b"],
        runs: [
            {flow_id: "login", pair: "nextcloud-v34", execution_id: "exec-aaa",
             cell_id: "cell-a", artifact_name: "cell-login-nc-v34", status: "passed",
             exit_code: 0, started_at: $ts, finished_at: $ts}
        ],
        passed_count: 1, failed_count: 0, blocked_count: 1,
    }
    $suite_record | to json --indent 2 | save --force ($runs_dir | path join $"($suite_id).json")
    $suite_id | save --force ($suites_dir | path join "LATEST_SUITE_ID")

    # Write CI aggregated manifest with one passed and one missing result.
    let agg_dir = ($artifacts_root | path join "suites/aggregated")
    mkdir $agg_dir
    let ci_agg = {
        schema_version: 1, generated_at: $ts, suite_id: $suite_id,
        producer: {name: "ocmts-aggregator", version: "0.1.0"},
        flows: {login: {id: "login"}},
        cells: {"cell-a": {id: "cell-a", flow_id: "login", pair: "nextcloud-v34", artifact_name: "cell-login-nc-v34"}},
        runs: {},
        results: {
            "result-a": {
                schema_version: 1, id: "result-a", run_id: "exec-aaa",
                execution_id: "exec-aaa", cell_id: "cell-a",
                exit_code: 0, status: "passed", finished_at: $ts, failure_reason: "",
            }
            "result-missing-cell-b": {
                schema_version: 1, id: "result-missing-cell-b", run_id: "",
                execution_id: "", cell_id: "cell-b",
                exit_code: 1, status: "missing", finished_at: $ts,
                failure_reason: "cell had no recorded outcome",
            }
        },
        indexes: {latest_terminal_result_by_cell: {}},
        aggregate_status: "missing",
    }
    $ci_agg | to json --indent 2 | save --force ($agg_dir | path join "suite-manifest.v1.json")

    ingest-site $artifacts_root $rules $tmp $public_dir --latest-suite

    let site_manifest_path = ($public_dir | path join "suite-manifest.v1.json")
    let site_manifest_exists = ($site_manifest_path | path exists)
    let site_manifest = if $site_manifest_exists { open $site_manifest_path } else { {} }
    let result_statuses = ($site_manifest.results? | default {} | transpose k v | each {|r| $r.v.status? | default ""})

    let site_cell_ids = ($site_manifest.cells? | default {} | columns)
    let site_flow_ids = ($site_manifest.flows? | default {} | columns)
    let site_run_cols = (
        $site_manifest.runs? | default {}
        | transpose _ run | get run? | default {}
        | columns | sort
    )
    let removed_run_fields = ["images" "images_provenance" "stack_def_sha256" "stack_env_sha256"]
    let present_removed = ($removed_run_fields | where {|k| $k in $site_run_cols})

    ^rm -rf $tmp
    [
        (assert-truthy $site_manifest_exists
            "ingest-site writes public/suite-manifest.v1.json")
        (assert-truthy ("passed" in $result_statuses)
            "site manifest contains passed result from actual run")
        (assert-truthy ("missing" in $result_statuses)
            "site manifest preserves missing result injected from CI aggregate manifest")
        (assert-eq ($result_statuses | where {|s| $s == "missing"} | length) 1
            "exactly one missing result is preserved in site manifest")
        (assert-truthy ("cell-b" in $site_cell_ids)
            "site manifest cells has entry for missing cell-b (stub from ci_agg)")
        (assert-truthy ("login" in $site_flow_ids)
            "site manifest flows retains login flow after missing injection")
        (assert-eq ($present_removed | length) 0
            "public manifest run entries omit images, images_provenance, stack_def_sha256, stack_env_sha256")
    ]
}

def test-ingest-missing-injection-cell-list-fallback [] {
    test-log "\n[test-ingest-missing-injection-cell-list-fallback]"
    use ../../lib/site/ingest.nu [ingest-site]
    let tmp = (^mktemp -d | str trim)
    materialize-provenance-stubs $tmp
    patch-flow-glyph-ids $tmp
    let artifacts_root = ($tmp | path join "artifacts")
    let public_dir = ($tmp | path join "public")
    let ts = "2026-01-01T00:00:00Z"
    let suite_id = "20260101t000000-aabbccee"

    # Matrix rules record with one cell: login__nextcloud-v34 (flow_id=login, pair=nextcloud-v34).
    let rules = {matrix: {login__nextcloud: {
        enabled: true,
        flow_id: "login",
        browsers: ["chrome"],
        sender: {platform: "nextcloud", version_lines: ["v34"]},
    }}}

    # Per-run manifest for cell-a (passed).
    let run_dir = ($artifacts_root | path join "login" "nextcloud-v34" "exec-aaa")
    mkdir ($run_dir | path join "meta")
    let run_manifest = {
        schema_version: 1, generated_at: $ts, execution_context: {},
        flows: {login: {id: "login"}},
        cells: {"cell-a": {id: "cell-a", flow_id: "login", pair: "nextcloud-v34",
                           artifact_name: "cell-login-nc-v34"}},
        runs: {"exec-aaa": {id: "exec-aaa", cell_id: "cell-a",
                            started_at: $ts, finished_at: $ts}},
        results: {"result-a": {
            schema_version: 1, id: "result-a", run_id: "exec-aaa",
            execution_id: "exec-aaa", cell_id: "cell-a",
            exit_code: 0, status: "passed", finished_at: $ts, failure_reason: "",
            evidence: [],
        }},
        indexes: {latest_terminal_result_by_cell: {}},
    }
    $run_manifest | to json --indent 2 | save --force ($run_dir | path join "meta/suite-manifest.v1.json")

    # Suite index listing only cell-a; login__nextcloud-v34 is missing.
    let suites_dir = ($artifacts_root | path join "suites")
    let runs_dir = ($suites_dir | path join "runs")
    mkdir $runs_dir
    let suite_record = {
        schema_version: 2, suite_id: $suite_id, suite_kind: "aggregated",
        started_at: $ts, finished_at: $ts, status: "missing",
        scheduled_cells: ["cell-a" "login__nextcloud-v34"],
        runs: [{flow_id: "login", pair: "nextcloud-v34", execution_id: "exec-aaa",
                cell_id: "cell-a", artifact_name: "cell-login-nc-v34", status: "passed",
                exit_code: 0, started_at: $ts, finished_at: $ts}],
        passed_count: 1, failed_count: 0, blocked_count: 1,
    }
    $suite_record | to json --indent 2 | save --force ($runs_dir | path join $"($suite_id).json")
    $suite_id | save --force ($suites_dir | path join "LATEST_SUITE_ID")

    # CI aggregate manifest: cells has cell-a only (not login__nextcloud-v34).
    # Missing result references login__nextcloud-v34 so cell_list fallback fires.
    let agg_dir = ($artifacts_root | path join "suites/aggregated")
    mkdir $agg_dir
    let ci_agg = {
        schema_version: 1, generated_at: $ts, suite_id: $suite_id,
        producer: {name: "ocmts-aggregator", version: "0.1.0"},
        flows: {login: {id: "login"}},
        cells: {"cell-a": {id: "cell-a", flow_id: "login", pair: "nextcloud-v34",
                           artifact_name: "cell-login-nc-v34"}},
        runs: {},
        results: {
            "result-a": {
                schema_version: 1, id: "result-a", run_id: "exec-aaa",
                execution_id: "exec-aaa", cell_id: "cell-a",
                exit_code: 0, status: "passed", finished_at: $ts, failure_reason: "",
            },
            "result-missing-nc-v34": {
                schema_version: 1, id: "result-missing-nc-v34", run_id: "",
                execution_id: "", cell_id: "login__nextcloud-v34",
                exit_code: 1, status: "missing", finished_at: $ts,
                failure_reason: "cell had no recorded outcome",
            },
        },
        indexes: {latest_terminal_result_by_cell: {}},
        aggregate_status: "missing",
    }
    $ci_agg | to json --indent 2 | save --force ($agg_dir | path join "suite-manifest.v1.json")

    ingest-site $artifacts_root $rules $tmp $public_dir --latest-suite

    let site_manifest_path = ($public_dir | path join "suite-manifest.v1.json")
    let site_manifest_exists = ($site_manifest_path | path exists)
    let site_manifest = if $site_manifest_exists { open $site_manifest_path } else { {} }
    let injected_cell = ($site_manifest.cells? | default {} | get --optional "login__nextcloud-v34")

    ^rm -rf $tmp
    [
        (assert-truthy $site_manifest_exists
            "cell-list fallback: site manifest written")
        (assert-truthy ($injected_cell != null)
            "cell-list fallback: login__nextcloud-v34 present in cells")
        (assert-eq ($injected_cell.flow_id? | default "")
            "login"
            "cell-list fallback: flow_id from cell_list")
        (assert-eq ($injected_cell.pair? | default "")
            "nextcloud-v34"
            "cell-list fallback: pair from cell_list")
        (assert-eq ($injected_cell.artifact_name? | default "")
            "cell-login-nextcloud-v34"
            "cell-list fallback: artifact_name from cell_list")
        (assert-eq ($injected_cell.sender_platform? | default "")
            "nextcloud"
            "cell-list fallback: sender_platform from cell_list")
        (assert-eq ($injected_cell.sender_version? | default "")
            "v34"
            "cell-list fallback: sender_version from cell_list")
        (assert-eq ($injected_cell.browser? | default "")
            "chrome"
            "cell-list fallback: browser from cell_list")
        (assert-eq ($injected_cell.is_two_party? | default true)
            false
            "cell-list fallback: is_two_party from cell_list")
    ]
}

def main [] {
    test-log "=== CI Site-Ingest Tests ==="
    let results = (
        (test-ingest-missing-injection)
        | append (test-ingest-missing-injection-cell-list-fallback)
    ) | flatten
    run-suite "ci/site-ingest" $SUITE_PATH $results
}
