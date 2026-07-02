# Tests for the aggregated suite-manifest writer.
# Run: nu scripts/tests/site/manifest.nu

const SUITE_PATH = path self

use ../../lib/site/manifest.nu [build-aggregated-manifest]
use ../../lib/tests/assert.nu *
use ../../lib/tests/runner.nu [run-suite]

def ocmts-root [] {
    $SUITE_PATH | path dirname | path dirname | path dirname | path dirname
}

# build-aggregated-manifest stamps a uniform provenance block with empty sources.
def test-build-aggregated-manifest-provenance-shape [] {
    test-log "\n[test-build-aggregated-manifest-provenance-shape]"
    let out = (build-aggregated-manifest [] (ocmts-root))
    let cols = ($out | columns | sort)
    let rfc_re = '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{9}Z$'
    let rfc_match = ($out.generated_at | parse --regex $rfc_re)
    [
        (assert-eq $out.schema_version 1
            "schema_version is 1")
        (assert-eq $out.generator
            "scripts/lib/site/manifest.nu#build-aggregated-manifest"
            "generator points at this writer")
        (assert-eq $out.producer {name: "ocmts", version: "0.1.0"}
            "producer matches uniform constant")
        (assert-eq $out.sources []
            "aggregator has no fixed input sources")
        (assert-truthy (($rfc_match | length) == 1)
            "generated_at matches RFC3339 nanosecond format")
        (assert-truthy ("execution_context" in $cols)
            "execution_context preserved")
        (assert-truthy ("flows" in $cols)
            "flows preserved")
        (assert-truthy ("cells" in $cols)
            "cells preserved")
        (assert-truthy ("runs" in $cols)
            "runs preserved")
        (assert-truthy ("results" in $cols)
            "results preserved")
        (assert-truthy ("indexes" in $cols)
            "indexes preserved")
    ]
}

# Aggregated runs omit per-run image/hash fields; execution_context is injected.
def test-build-aggregated-manifest-run-shape [] {
    test-log "\n[test-build-aggregated-manifest-run-shape]"
    let tmp = (^mktemp -d | str trim)
    let ts = "2026-01-01T00:00:00Z"
    let run_dir = ($tmp | path join "login" "nextcloud-v34" "exec-aaa")
    mkdir ($run_dir | path join "meta")
    mkdir ($run_dir | path join "compose")
    let exec_ctx = {browser: "chrome", platform: "nextcloud"}
    let run_manifest = {
        schema_version: 1,
        generated_at: $ts,
        execution_context: $exec_ctx,
        flows: {login: {id: "login"}},
        cells: {"cell-a": {id: "cell-a", flow_id: "login", pair: "nextcloud-v34"}},
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
    {
        images: {sender: "ghcr.io/example/sender:tag"},
    } | to json --indent 2 | save --force ($run_dir | path join "meta/run.json")
    {
        schema_version: 1,
        stack_def_sha256: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
        stack_env_sha256: "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
    } | to json --indent 2 | save --force ($run_dir | path join "compose/manifest.v1.json")

    let entry = {
        manifest: $run_manifest,
        run_dir: $run_dir,
        artifact_name: "cell-login-nc-v34",
        exec_id: "exec-aaa",
        cell_id: "cell-a",
        result_id: "result-a",
        finished_at: $ts,
    }
    let out = (build-aggregated-manifest [$entry] (ocmts-root))
    let run_entry = ($out.runs | get "exec-aaa")
    let run_cols = ($run_entry | columns | sort)
    let removed = ["images" "images_provenance" "stack_def_sha256" "stack_env_sha256"]
    let present_removed = ($removed | where {|k| $k in $run_cols})

    ^rm -rf $tmp
    [
        (assert-eq ($out.runs | columns | length) 1
            "one aggregated run entry")
        (assert-eq ($present_removed | length) 0
            "aggregated run omits images, images_provenance, stack_def_sha256, stack_env_sha256")
        (assert-eq ($run_entry.execution_context? | default {})
            $exec_ctx
            "execution_context injected from per-run manifest")
        (assert-eq ($run_entry.id? | default "")
            "exec-aaa"
            "run id preserved")
        (assert-eq ($run_entry.cell_id? | default "")
            "cell-a"
            "cell_id preserved")
    ]
}

def main [] {
    test-log "=== site/manifest Tests ==="
    let results = (
        (test-build-aggregated-manifest-provenance-shape)
        | append (test-build-aggregated-manifest-run-shape)
    ) | flatten
    run-suite "site/manifest" $SUITE_PATH $results
}
