# Tests for run-metadata write-terminal-outcome and suite-index skipped support.
# Run: nu scripts/tests/run/metadata.nu
# Returns exit 0 on all pass, exit 1 with details on failure.

const SUITE_PATH = path self

use ../../lib/run/metadata.nu [
    write-terminal-outcome
    read-run-meta
    write-prepared-run
    resolve-matrix-key
]
use ../../lib/time/utc.nu [utc-now]
use ../../lib/ci/suite-stop-on-fail.nu [stop-on-fail-tail]
use ../../lib/suite/index.nu [
    init-suite-record
    finish-suite-record
    record-suite-run
    record-skipped-run
    record-blocked-run
    read-suite-record
    compute-suite-status
]
use ../../lib/run/status.nu [run-status-precedence]
use ../../lib/tests/assert.nu *
use ../../lib/tests/runner.nu [run-suite]

def fixture-suite-id [] {
    "20260101t120000-aabbccdd"
}

def fixture-skipped-cell [cell_id: string] {
    {
        cell_id: $cell_id,
        flow_id: "login",
        pair: "nextcloud-v34",
        execution_id: "20260101t120001-aabbccee",
        artifact_name: $"cell-login-nextcloud-v34",
    }
}

# ---- write-terminal-outcome tests ----

def test-write-terminal-outcome-run-shape [] {
    test-log "\n[test-write-terminal-outcome-run-shape]"
    let tmp = (^mktemp -d | str trim)
    let meta_dir = ($tmp | path join "meta")
    mkdir $meta_dir

    let ts = (utc-now)
    (write-terminal-outcome $tmp "exec-001" "login__nc-v34"
        "cell-login-nc-v34" $ts $ts "passed" 0 "stack-001" null
        --matrix-key "login__nextcloud")

    let run_path = ($tmp | path join "meta/run.json")
    let result_path = ($tmp | path join "meta/result.v1.json")
    let run_exists = ($run_path | path exists)
    let result_exists = ($result_path | path exists)
    let run = if $run_exists { open $run_path } else { {} }
    let result = if $result_exists { open $result_path } else { {} }

    ^rm -rf $tmp
    [
        (assert-truthy $run_exists
            "write-terminal-outcome creates meta/run.json")
        (assert-truthy $result_exists
            "write-terminal-outcome creates meta/result.v1.json")
        (assert-eq ($run.status? | default "") "passed"
            "run.json has correct status")
        (assert-eq ($run.exit_code? | default (-99)) 0
            "run.json has exit_code 0")
        (assert-eq ($run.execution_id? | default "") "exec-001"
            "run.json has execution_id")
        (assert-eq ($run.cell_id? | default "") "login__nc-v34"
            "run.json has cell_id")
        (assert-eq ($run.matrix_key? | default "") "login__nextcloud"
            "run.json has matrix_key when provided")
        (assert-eq ($result.status? | default "") "passed"
            "result.v1.json has correct status")
        (assert-eq ($result.exit_code? | default (-99)) 0
            "result.v1.json has exit_code 0")
        (assert-eq ($result.execution_id? | default "") "exec-001"
            "result.v1.json has execution_id")
        (assert-eq ($result.id? | default "") "result-exec-001"
            "result.v1.json has id=result-<execution_id>")
        (assert-eq ($result.run_id? | default "") "exec-001"
            "result.v1.json has run_id matching execution_id")
        (assert-eq ($result.cell_id? | default "") "login__nc-v34"
            "result.v1.json has cell_id")
        (assert-eq ($result.matrix_key? | default "") "login__nextcloud"
            "result.v1.json has matrix_key when provided")
        (assert-eq ($result.artifact_name? | default "") "cell-login-nc-v34"
            "result.v1.json has artifact_name")
        (assert-eq ($result.schema_version? | default 0) 1
            "result.v1.json has schema_version=1")
        (assert-eq ($result.warnings? | default null) []
            "result.v1.json has warnings=[]")
        (assert-not-null ($result.execution_context? | default null)
            "result.v1.json has execution_context")
        (assert-not-null ($result.evidence? | default null)
            "result.v1.json has evidence record")
        (assert-truthy (not ($result | columns | any {|c| $c == "verdict"}))
            "minimal result.v1.json (no Cypress run) omits verdict field")
    ]
}

def test-write-terminal-outcome-inherits-matrix-key-from-prepared-run [] {
    test-log "\n[test-write-terminal-outcome-inherits-matrix-key-from-prepared-run]"
    let tmp = (^mktemp -d | str trim)
    mkdir ($tmp | path join "meta")
    let ts = (utc-now)
    (write-prepared-run $tmp "exec-prep-001" "login__nc-v34"
        "cell-login-nc-v34" $ts "stack-prep"
        --matrix-key "login__nextcloud")
    (write-terminal-outcome $tmp "exec-prep-001" "login__nc-v34"
        "cell-login-nc-v34" $ts $ts "infra-failed" 1 "stack-prep" null
        --phase "platform-up" --fail-error "simulated failure")

    let run = (open ($tmp | path join "meta/run.json"))
    let result = (open ($tmp | path join "meta/result.v1.json"))
    ^rm -rf $tmp
    [
        (assert-eq ($run.matrix_key? | default "") "login__nextcloud"
            "terminal run.json inherits matrix_key from prepared run")
        (assert-eq ($result.matrix_key? | default "") "login__nextcloud"
            "terminal result.v1.json inherits matrix_key from prepared run")
    ]
}

def test-write-terminal-outcome-failure-shape [] {
    test-log "\n[test-write-terminal-outcome-failure-shape]"
    let tmp = (^mktemp -d | str trim)
    let meta_dir = ($tmp | path join "meta")
    mkdir $meta_dir

    let ts = (utc-now)
    (write-terminal-outcome $tmp "exec-002" "login__nc-v34"
        "cell-login-nc-v34" $ts $ts "infra-failed" 1 "stack-002" null
        --phase "platform-up" --fail-error "docker up failed")

    let run_path = ($tmp | path join "meta/run.json")
    let result_path = ($tmp | path join "meta/result.v1.json")
    let run = if ($run_path | path exists) { open $run_path } else { {} }
    let result = if ($result_path | path exists) { open $result_path } else { {} }

    ^rm -rf $tmp
    [
        (assert-eq ($run.status? | default "") "infra-failed"
            "run.json has infra-failed status")
        (assert-eq ($run.exit_code? | default 0) 1
            "run.json has exit_code 1")
        (assert-eq ($run.phase? | default "") "platform-up"
            "run.json has phase field")
        (assert-eq ($run.error? | default "") "docker up failed"
            "run.json has error field from --fail-error")
        (assert-eq ($result.status? | default "") "infra-failed"
            "result.v1.json mirrors status")
        (assert-eq ($result.exit_code? | default 0) 1
            "result.v1.json mirrors exit_code")
        (assert-truthy (not ($result | columns | any {|c| $c == "verdict"}))
            "infra-failed result.v1.json omits verdict field")
        (assert-eq ($result.warnings? | default null) []
            "result.v1.json has warnings=[]")
    ]
}

def test-write-terminal-outcome-suite-fields [] {
    test-log "\n[test-write-terminal-outcome-suite-fields]"
    let tmp = (^mktemp -d | str trim)
    let meta_dir = ($tmp | path join "meta")
    mkdir $meta_dir

    let ts = (utc-now)
    let sid = (fixture-suite-id)
    (write-terminal-outcome $tmp "exec-003" "login__nc-v34"
        "cell-login-nc-v34" $ts $ts "passed" 0 "stack-003" null
        --suite-id $sid --suite-kind "suite")

    let run_path = ($tmp | path join "meta/run.json")
    let result_path = ($tmp | path join "meta/result.v1.json")
    let run = if ($run_path | path exists) { open $run_path } else { {} }
    let result = if ($result_path | path exists) { open $result_path } else { {} }

    ^rm -rf $tmp
    [
        (assert-eq ($run.suite_id? | default "") $sid
            "run.json has suite_id when provided")
        (assert-eq ($run.suite_kind? | default "") "suite"
            "run.json has suite_kind")
        (assert-eq ($result.suite_id? | default "") $sid
            "result.v1.json has suite_id when provided")
        (assert-eq ($result.suite_kind? | default "") "suite"
            "result.v1.json has suite_kind")
    ]
}

# ---- suite-index tests using real functions via OCMTS_ROOT env ----

def test-finish-suite-record-skipped-count [] {
    test-log "\n[test-finish-suite-record-skipped-count]"
    let tmp = (^mktemp -d | str trim)
    let suite_id = (fixture-suite-id)
    let results = (with-env {OCMTS_ROOT: $tmp} {
        init-suite-record $suite_id "suite" ["a" "b" "c" "d"]
        finish-suite-record $suite_id 1 1 0 2
        let rec = (read-suite-record $suite_id)
        [
            (assert-eq ($rec.skipped_count? | default (-1)) 2
                "finish-suite-record persists skipped_count=2")
            (assert-eq ($rec.passed_count? | default (-1)) 1
                "finish-suite-record persists passed_count=1")
            (assert-eq ($rec.failed_count? | default (-1)) 1
                "finish-suite-record persists failed_count=1")
            (assert-eq ($rec.status? | default "") "failed"
                "status is failed when failed > 0 even with skipped cells")
        ]
    })
    ^rm -rf $tmp
    $results
}

def test-record-skipped-run-appends-entry [] {
    test-log "\n[test-record-skipped-run-appends-entry]"
    let tmp = (^mktemp -d | str trim)
    let suite_id = (fixture-suite-id)
    let cell = (fixture-skipped-cell "login__nc-v34")
    let results = (with-env {OCMTS_ROOT: $tmp} {
        init-suite-record $suite_id "suite" [$cell.cell_id]
        let skipped_at = (utc-now)
        record-skipped-run $suite_id $cell $skipped_at
        let rec = (read-suite-record $suite_id)
        let runs = ($rec.runs? | default [])
        let skipped_entries = ($runs | where status == "skipped")
        [
            (assert-eq ($skipped_entries | length) 1
                "one skipped entry appended to suite record runs")
            (assert-eq ($skipped_entries | first | get cell_id) "login__nc-v34"
                "skipped entry has correct cell_id")
            (assert-eq ($skipped_entries | first | get exit_code) (-1)
                "skipped entry has exit_code -1")
            (assert-eq ($skipped_entries | first | get started_at) ""
                "skipped entry has empty started_at")
        ]
    })
    ^rm -rf $tmp
    $results
}

def test-record-blocked-run-appends-entry [] {
    test-log "\n[test-record-blocked-run-appends-entry]"
    let tmp = (^mktemp -d | str trim)
    let suite_id = (fixture-suite-id)
    let cell = (fixture-skipped-cell "login__nc-v34")
    let results = (with-env {OCMTS_ROOT: $tmp} {
        init-suite-record $suite_id "suite" [$cell.cell_id]
        let blocked_at = (utc-now)
        record-blocked-run $suite_id $cell $blocked_at
        let rec = (read-suite-record $suite_id)
        let runs = ($rec.runs? | default [])
        let blocked_entries = ($runs | where status == "blocked")
        [
            (assert-eq ($blocked_entries | length) 1
                "one blocked entry appended to suite record runs")
            (assert-eq ($blocked_entries | first | get cell_id) "login__nc-v34"
                "blocked entry has correct cell_id")
            (assert-eq ($blocked_entries | first | get exit_code) (-1)
                "blocked entry has exit_code -1")
            (assert-eq ($blocked_entries | first | get started_at) ""
                "blocked entry has empty started_at")
            (assert-eq ($blocked_entries | first | get flow_id) "login"
                "blocked entry preserves flow_id")
            (assert-eq ($blocked_entries | first | get execution_id) "20260101t120001-aabbccee"
                "blocked entry preserves execution_id")
        ]
    })
    ^rm -rf $tmp
    $results
}

# Focused precedence regression: blocked sits between passed and failed.
def test-blocked-status-precedence [] {
    test-log "\n[test-blocked-status-precedence]"
    [
        (assert-eq (compute-suite-status ["passed" "blocked"]) "blocked"
            "blocked beats passed")
        (assert-eq (compute-suite-status ["blocked" "failed"]) "failed"
            "failed beats blocked")
    ]
}

# Thin delegation check: compute-suite-status must agree with run-status-precedence.
# Canonical precedence coverage lives in scripts/tests/run/status.nu.
def test-compute-suite-status-delegates [] {
    test-log "\n[test-compute-suite-status-delegates]"
    let input = ["passed" "failed" "blocked"]
    [
        (assert-eq (compute-suite-status $input) (run-status-precedence $input)
            "compute-suite-status delegates to run-status-precedence")
    ]
}

# Verifies the corrected stop-on-fail logic: every tail cell becomes skipped,
# including a cell that would have been blocked by a prior failure on the normal path.
def test-stop-on-fail-all-tail-cells-skipped-including-would-be-blocked [] {
    test-log "\n[test-stop-on-fail-all-tail-cells-skipped-including-would-be-blocked]"
    let tmp = (^mktemp -d | str trim)
    let suite_id = (fixture-suite-id)

    # Three planned cells:
    #   a - fails (no deps)
    #   b - depends on a (would be blocked on normal path)
    #   c - no deps (independent)
    # stop-on-fail fires after a; b and c should both be recorded as skipped.
    let cells = [
        {cell_id: "a", flow_id: "login", pair: "nc-v34",
         execution_id: "exec-a", artifact_name: "cell-a"}
        {cell_id: "b", flow_id: "share-with", pair: "nc-v34__nc-v34",
         execution_id: "exec-b", artifact_name: "cell-b"}
        {cell_id: "c", flow_id: "login", pair: "nc-v34",
         execution_id: "exec-c", artifact_name: "cell-c"}
    ]

    # Call the real production helper with the failed cell identity so this
    # test covers the production tail-selection path without synthetic indices.
    let failed_cell_id = "a"
    let remaining = (stop-on-fail-tail $cells $failed_cell_id)

    let results = (with-env {OCMTS_ROOT: $tmp} {
        init-suite-record $suite_id "suite" ($cells | each {|c| $c.cell_id})
        let skipped_at = (utc-now)
        for tail_cell in $remaining {
            record-skipped-run $suite_id $tail_cell $skipped_at
        }
        finish-suite-record $suite_id 0 1 0 ($remaining | length)
        let rec = (read-suite-record $suite_id)
        let run_statuses = ($rec.runs? | default [] | each {|r| $r.status})
        let run_cell_ids = ($rec.runs? | default [] | each {|r| $r.cell_id})
        let skipped_ids = ($remaining | each {|c| $c.cell_id})
        [
            (assert-eq ($skipped_ids | length) 2
                "2 tail cells are skipped after stop-on-fail at first cell")
            (assert-truthy ("b" in $skipped_ids)
                "would-be-blocked cell b is in skipped list, not blocked")
            (assert-truthy ("c" in $skipped_ids)
                "independent cell c is also skipped")
            (assert-eq ($rec.skipped_count? | default (-1)) 2
                "suite record skipped_count=2")
            (assert-eq ($run_statuses | where {|s| $s == "skipped"} | length) 2
                "two skipped run entries recorded")
            (assert-truthy ("b" in $run_cell_ids)
                "cell b has a run entry with skipped status")
            (assert-truthy ("c" in $run_cell_ids)
                "cell c has a run entry with skipped status")
            (assert-eq ($run_statuses | where {|s| $s == "blocked"} | length) 0
                "no blocked run entries - stop-on-fail tail is all skipped")
        ]
    })
    ^rm -rf $tmp
    $results
}

# ---- resolve-matrix-key tests ----

def test-resolve-matrix-key-explicit-precedence [] {
    test-log "\n[test-resolve-matrix-key-explicit-precedence]"
    let tmp = (^mktemp -d | str trim)
    mkdir ($tmp | path join "meta")
    ({
        matrix_key: "login__from-run"
    } | to json) | save --force ($tmp | path join "meta/run.json")
    ({
        matrix_key: "login__from-cell"
        cell_id: "login__nc-v34"
    } | to json) | save --force ($tmp | path join "meta/cell.json")
    let mk = (resolve-matrix-key $tmp --explicit "login__explicit")
    ^rm -rf $tmp
    [
        (assert-eq $mk "login__explicit"
            "explicit --matrix-key wins over run.json and cell.json")
    ]
}

def test-resolve-matrix-key-run-json-only [] {
    test-log "\n[test-resolve-matrix-key-run-json-only]"
    let tmp = (^mktemp -d | str trim)
    mkdir ($tmp | path join "meta")
    ({
        matrix_key: "login__from-run"
    } | to json) | save --force ($tmp | path join "meta/run.json")
    ({
        matrix_key: "login__from-cell"
        cell_id: "login__nc-v34"
    } | to json) | save --force ($tmp | path join "meta/cell.json")
    let mk = (resolve-matrix-key $tmp)
    ^rm -rf $tmp
    [
        (assert-eq $mk "login__from-run"
            "resolve-matrix-key reads run.json and ignores cell.json")
    ]
}

def test-resolve-matrix-key-empty-without-run-json [] {
    test-log "\n[test-resolve-matrix-key-empty-without-run-json]"
    let tmp = (^mktemp -d | str trim)
    mkdir ($tmp | path join "meta")
    ({
        matrix_key: "login__from-cell"
        cell_id: "login__nc-v34"
    } | to json) | save --force ($tmp | path join "meta/cell.json")
    let mk = (resolve-matrix-key $tmp)
    ^rm -rf $tmp
    [
        (assert-eq $mk ""
            "resolve-matrix-key returns empty when run.json has no matrix_key")
    ]
}

def test-resolve-matrix-key-errors-on-malformed-run-json [] {
    test-log "\n[test-resolve-matrix-key-errors-on-malformed-run-json]"
    let tmp = (^mktemp -d | str trim)
    mkdir ($tmp | path join "meta")
    "{ not valid json" | save --force ($tmp | path join "meta/run.json")
    let result = (try { resolve-matrix-key $tmp; "no-error" } catch {|e| "error"})
    ^rm -rf $tmp
    [
        (assert-eq $result "error"
            "resolve-matrix-key fails fast on malformed meta/run.json")
    ]
}

# ---- read-run-meta tests ----

def test-read-run-meta-happy-path [] {
    test-log "\n[test-read-run-meta-happy-path]"
    let tmp = (^mktemp -d | str trim)
    mkdir ($tmp | path join "meta")
    let payload = {schema_version: 1, execution_id: "exec-001", stack_id: "ocmts-stack", status: "active"}
    $payload | to json | save --force ($tmp | path join "meta/run.json")
    let meta = (read-run-meta $tmp)
    ^rm -rf $tmp
    [
        (assert-eq ($meta.stack_id? | default "") "ocmts-stack"
            "read-run-meta returns stack_id from run.json")
        (assert-eq ($meta.status? | default "") "active"
            "read-run-meta returns full record including status")
    ]
}

def test-read-run-meta-missing-file-errors [] {
    test-log "\n[test-read-run-meta-missing-file-errors]"
    let tmp = (^mktemp -d | str trim)
    mkdir ($tmp | path join "meta")
    let result = (try { read-run-meta $tmp; "no-error" } catch {|e| "error"})
    ^rm -rf $tmp
    [
        (assert-eq $result "error"
            "read-run-meta errors when meta/run.json is absent")
    ]
}

def test-read-run-meta-missing-stack-id-errors [] {
    test-log "\n[test-read-run-meta-missing-stack-id-errors]"
    let tmp = (^mktemp -d | str trim)
    mkdir ($tmp | path join "meta")
    {schema_version: 1, execution_id: "exec-001"} | to json | save --force ($tmp | path join "meta/run.json")
    let result = (try { read-run-meta $tmp; "no-error" } catch {|e| "error"})
    ^rm -rf $tmp
    [
        (assert-eq $result "error"
            "read-run-meta errors when stack_id is absent")
    ]
}

def test-read-run-meta-empty-stack-id-errors [] {
    test-log "\n[test-read-run-meta-empty-stack-id-errors]"
    let tmp = (^mktemp -d | str trim)
    mkdir ($tmp | path join "meta")
    {schema_version: 1, execution_id: "exec-001", stack_id: ""} | to json | save --force ($tmp | path join "meta/run.json")
    let result = (try { read-run-meta $tmp; "no-error" } catch {|e| "error"})
    ^rm -rf $tmp
    [
        (assert-eq $result "error"
            "read-run-meta errors when stack_id is empty string")
    ]
}

def main [] {
    test-log "=== Run Metadata + Suite Index Tests ==="
    let results = (
        (test-write-terminal-outcome-run-shape)
        | append (test-write-terminal-outcome-inherits-matrix-key-from-prepared-run)
        | append (test-write-terminal-outcome-failure-shape)
        | append (test-write-terminal-outcome-suite-fields)
        | append (test-finish-suite-record-skipped-count)
        | append (test-record-skipped-run-appends-entry)
        | append (test-record-blocked-run-appends-entry)
        | append (test-blocked-status-precedence)
        | append (test-compute-suite-status-delegates)
        | append (test-stop-on-fail-all-tail-cells-skipped-including-would-be-blocked)
        | append (test-resolve-matrix-key-explicit-precedence)
        | append (test-resolve-matrix-key-run-json-only)
        | append (test-resolve-matrix-key-empty-without-run-json)
        | append (test-resolve-matrix-key-errors-on-malformed-run-json)
        | append (test-read-run-meta-happy-path)
        | append (test-read-run-meta-missing-file-errors)
        | append (test-read-run-meta-missing-stack-id-errors)
        | append (test-read-run-meta-empty-stack-id-errors)
    ) | flatten
    run-suite "run/metadata" $SUITE_PATH $results
}
