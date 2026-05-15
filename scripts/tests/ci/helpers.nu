# Helper and small regression tests that do not belong in ci/planner.
# Covers: resolve-source-run passthrough, prereq-status evaluation,
# read-cells-json compact output, and find-suite-dirs exec-dir discovery.
# Run: nu scripts/tests/ci/helpers.nu

const SUITE_PATH = path self

use ../../lib/ci/source-run.nu [resolve-source-run-id]
use ../../lib/ci/prereq-status.nu [eval-prereq-status]
use ../../lib/tests/assert.nu *
use ../../lib/tests/runner.nu [run-suite]

# Build a realistic nested prereq artifact under dep_dir, mirroring the
# downloaded layout: dep_dir/<flow>/<pair>/<exec-id>/meta/result.v1.json.
def make-prereq-result [dep_dir: string, result_json: string] {
    let nested = ($dep_dir | path join "login" "nc-v34" "exec-abc123" "meta")
    mkdir $nested
    $result_json | save ($nested | path join "result.v1.json")
}

def test-resolve-source-run-passthrough [] {
    test-log "\n[test-resolve-source-run-passthrough]"
    let id = (resolve-source-run-id "99887766" "ci-matrix.yml" "main")
    [
        (assert-eq $id "99887766"
            "explicit run-id is returned unchanged without GH lookup")
    ]
}

def test-prereq-status-no-deps [] {
    test-log "\n[test-prereq-status-no-deps]"
    let reason = (eval-prereq-status [] "/nonexistent")
    [
        (assert-eq $reason "" "empty dep list returns empty reason")
    ]
}

def test-prereq-status-missing-artifact [] {
    test-log "\n[test-prereq-status-missing-artifact]"
    let tmp = (^mktemp -d | str trim)
    # No subdirectory created under tmp for cell-a - simulates a failed download.
    let reason = (eval-prereq-status ["cell-a"] $tmp)
    ^rm -rf $tmp
    [
        (assert-eq $reason
            "prerequisite cell-a artifact missing or download failed"
            "missing result file returns artifact-missing reason")
    ]
}

def test-prereq-status-non-passed [] {
    test-log "\n[test-prereq-status-non-passed]"
    let tmp = (^mktemp -d | str trim)
    make-prereq-result ($tmp | path join "cell-a") ({status: "failed"} | to json)
    let reason = (eval-prereq-status ["cell-a"] $tmp)
    ^rm -rf $tmp
    [
        (assert-eq $reason
            "prerequisite cell-a had status: failed"
            "non-passed status returns status reason")
    ]
}

def test-prereq-status-all-passed [] {
    test-log "\n[test-prereq-status-all-passed]"
    let tmp = (^mktemp -d | str trim)
    make-prereq-result ($tmp | path join "cell-a") ({status: "passed"} | to json)
    make-prereq-result ($tmp | path join "cell-b") ({status: "passed"} | to json)
    let reason = (eval-prereq-status ["cell-a" "cell-b"] $tmp)
    ^rm -rf $tmp
    [
        (assert-eq $reason "" "all passed deps return empty reason")
    ]
}

def test-prereq-status-stops-at-first-failure [] {
    test-log "\n[test-prereq-status-stops-at-first-failure]"
    let tmp = (^mktemp -d | str trim)
    make-prereq-result ($tmp | path join "cell-a") ({status: "passed"} | to json)
    # cell-b has no artifact dir - simulates missing download
    let reason = (eval-prereq-status ["cell-a" "cell-b"] $tmp)
    ^rm -rf $tmp
    [
        (assert-eq $reason
            "prerequisite cell-b artifact missing or download failed"
            "stops at first failure after a passing dep")
    ]
}

def test-prereq-status-skips-whitespace-deps [] {
    test-log "\n[test-prereq-status-skips-whitespace-deps]"
    let tmp = (^mktemp -d | str trim)
    make-prereq-result ($tmp | path join "cell-a") ({status: "passed"} | to json)
    # leading/trailing spaces around cell-a should still resolve correctly
    let reason = (eval-prereq-status [" cell-a " "  "] $tmp)
    ^rm -rf $tmp
    [
        (assert-eq $reason "" "whitespace-padded dep trimmed correctly; empty entry skipped")
    ]
}

def test-prereq-status-unknown-status-field [] {
    test-log "\n[test-prereq-status-unknown-status-field]"
    let tmp = (^mktemp -d | str trim)
    # result.v1.json with no status field -> defaults to "unknown"
    make-prereq-result ($tmp | path join "cell-a") ({} | to json)
    let reason = (eval-prereq-status ["cell-a"] $tmp)
    ^rm -rf $tmp
    [
        (assert-eq $reason
            "prerequisite cell-a had status: unknown"
            "missing status field treated as unknown and reported")
    ]
}

# Regression: read-cells-json must emit compact one-line JSON, not pretty-printed.
# The --raw flag on `to json` is what makes it compact; this test guards against
# losing that flag and breaking GitHub Actions output consumption.
def test-read-cells-json-compact-output [] {
    test-log "\n[test-read-cells-json-compact-output]"
    let tmp = (^mktemp -d | str trim)
    let json_file = ($tmp | path join "cells.json")
    ({a: 1, items: [1 2 3]} | to json | save $json_file)
    let script = (
        $SUITE_PATH | path dirname
        | path join ".." ".." "domains" "ci" "read-cells-json.nu"
        | path expand
    )
    let out = (^nu $script $json_file | str trim)
    ^rm -rf $tmp
    [
        (assert-truthy (not ($out | str contains "\n"))
            "output has no newlines (compact, not pretty-printed JSON)")
        (assert-truthy ($out | str starts-with "{")
            "output starts with { (valid JSON object)")
        (assert-eq ($out | from json | get a) 1
            "output is valid JSON with correct content")
    ]
}

# Regression: find-suite-dirs must return the exec dir (<exec>) when manifests
# live at <exec>/meta/suite-manifest.v1.json, not the intermediate <exec>/meta.
def test-find-suite-dirs-discovers-exec-not-meta [] {
    test-log "\n[test-find-suite-dirs-discovers-exec-not-meta]"
    let tmp = (^mktemp -d | str trim)
    mkdir ($tmp | path join "run-001" "meta")
    mkdir ($tmp | path join "run-002" "meta")
    ({} | to json | save ($tmp | path join "run-001" "meta" "suite-manifest.v1.json"))
    ({} | to json | save ($tmp | path join "run-002" "meta" "suite-manifest.v1.json"))
    let script = (
        $SUITE_PATH | path dirname
        | path join ".." ".." "domains" "ci" "find-suite-dirs.nu"
        | path expand
    )
    let dirs = (^nu $script $tmp | lines | where {|l| ($l | str trim) != ""})
    let expected_001 = ($tmp | path join "run-001")
    let expected_002 = ($tmp | path join "run-002")
    ^rm -rf $tmp
    [
        (assert-eq ($dirs | length) 2
            "discovers exactly two execution dirs")
        (assert-list-contains $dirs $expected_001
            "run-001 exec dir is discovered, not run-001/meta")
        (assert-list-contains $dirs $expected_002
            "run-002 exec dir is discovered, not run-002/meta")
        (assert-truthy (not ($dirs | any {|d| $d | str ends-with "meta"}))
            "no discovered dir ends with /meta")
    ]
}

def main [] {
    test-log "=== CI helper and regression tests ==="
    let results = (
        (test-resolve-source-run-passthrough)
        | append (test-prereq-status-no-deps)
        | append (test-prereq-status-missing-artifact)
        | append (test-prereq-status-non-passed)
        | append (test-prereq-status-all-passed)
        | append (test-prereq-status-stops-at-first-failure)
        | append (test-prereq-status-skips-whitespace-deps)
        | append (test-prereq-status-unknown-status-field)
        | append (test-read-cells-json-compact-output)
        | append (test-find-suite-dirs-discovers-exec-not-meta)
    ) | flatten
    run-suite "ci/helpers" $SUITE_PATH $results
}
