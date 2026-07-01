# write-compose-manifest / read-compose-manifest roundtrip tests.
# Run: nu scripts/tests/services/compose-manifest.nu
# Returns exit 0 on all pass, exit 1 with details on failure.

const SUITE_PATH = path self

use ../../lib/services/compose-files.nu [
    write-compose-manifest read-compose-manifest
]
use ../../lib/tests/assert.nu *
use ../../lib/tests/runner.nu [run-suite]

# Create a temp dir with compose/inputs/ populated from overlays record.
# Keys are filenames; values are file contents. stack.env added when with_env.
def make-fixture [overlays: record, with_env: bool] {
    let tmp = ($nu.temp-dir | path join $"compose-manifest-test-(random uuid)")
    let inputs = ($tmp | path join "compose" "inputs")
    mkdir $inputs
    for k in ($overlays | columns) {
        ($overlays | get $k) | save --force ($inputs | path join $k)
    }
    if $with_env {
        "STACK_ENV_FIXTURE=v1" | save --force ($inputs | path join "stack.env")
    }
    $tmp
}

# Schema fields, stack_id, applied_inputs, resolved_files, and hash lengths.
def test-writer-roundtrip [] {
    test-log "\n[test-writer-roundtrip]"
    let tmp = (make-fixture {exec.yml: "a", sender.yml: "b"} true)
    write-compose-manifest $tmp "stack-abc" ["exec.yml" "sender.yml"] "" ["compose.resolved.yml"]
    let m = (read-compose-manifest $tmp)
    let results = [
        (assert-eq $m.schema_version 1 "schema_version is 1")
        (assert-eq $m.stack_id "stack-abc" "stack_id matches")
        (assert-eq $m.applied_inputs [
            "config/compose/base.yml"
            "inputs/exec.yml"
            "inputs/sender.yml"
        ] "applied_inputs order and values")
        (assert-eq $m.resolved_files ["compose.resolved.yml"] "resolved_files")
        (assert-eq $m.base "config/compose/base.yml" "base field")
        (assert-truthy (($m.captured_at | str length) > 0) "captured_at non-empty")
        (assert-truthy (($m.stack_def_sha256 | str length) == 64) "stack_def_sha256 is 64 hex chars")
        (assert-truthy (($m.stack_env_sha256 | str length) == 64) "stack_env_sha256 is 64 hex chars")
    ]
    rm -rf $tmp
    $results
}

# Changing stack.env changes env hash but not def hash.
def test-stack-def-hash-stable-across-env-change [] {
    test-log "\n[test-stack-def-hash-stable-across-env-change]"
    let tmp = (make-fixture {exec.yml: "a", sender.yml: "b"} true)
    write-compose-manifest $tmp "sid" ["exec.yml" "sender.yml"] "" []
    let m = (read-compose-manifest $tmp)
    let def_a = $m.stack_def_sha256
    let env_a = $m.stack_env_sha256
    "y" | save --force ($tmp | path join "compose" "inputs" "stack.env")
    write-compose-manifest $tmp "sid" ["exec.yml" "sender.yml"] "" []
    let m2 = (read-compose-manifest $tmp)
    let results = [
        (assert-eq $m2.stack_def_sha256 $def_a "def hash unchanged when only env changes")
        (assert-truthy ($m2.stack_env_sha256 != $env_a) "env hash changes when stack.env content changes")
    ]
    rm -rf $tmp
    $results
}

# stack_env_sha256 is empty string when stack.env is absent.
def test-stack-env-hash-empty-when-missing [] {
    test-log "\n[test-stack-env-hash-empty-when-missing]"
    let tmp = (make-fixture {exec.yml: "a", sender.yml: "b"} false)
    write-compose-manifest $tmp "sid" ["exec.yml" "sender.yml"] "" []
    let m = (read-compose-manifest $tmp)
    let results = [
        (assert-eq $m.stack_env_sha256 "" "stack_env_sha256 is empty when stack.env absent")
    ]
    rm -rf $tmp
    $results
}

# Changing an overlay file changes the def hash.
def test-stack-def-hash-changes-when-overlay-changes [] {
    test-log "\n[test-stack-def-hash-changes-when-overlay-changes]"
    let tmp = (make-fixture {exec.yml: "a", sender.yml: "b"} false)
    write-compose-manifest $tmp "sid" ["exec.yml" "sender.yml"] "" []
    let m = (read-compose-manifest $tmp)
    let def_a = $m.stack_def_sha256
    "c" | save --force ($tmp | path join "compose" "inputs" "exec.yml")
    write-compose-manifest $tmp "sid" ["exec.yml" "sender.yml"] "" []
    let m2 = (read-compose-manifest $tmp)
    let results = [
        (assert-truthy ($m2.stack_def_sha256 != $def_a) "def hash changes when overlay content changes")
    ]
    rm -rf $tmp
    $results
}

# runner_fname appends to applied_inputs and is included in def hash.
def test-runner-fname-appends-to-applied-inputs [] {
    test-log "\n[test-runner-fname-appends-to-applied-inputs]"
    let tmp = (make-fixture {exec.yml: "a", sender.yml: "b", "runner-ci.yml": "r"} false)
    write-compose-manifest $tmp "sid" ["exec.yml" "sender.yml"] "runner-ci.yml" ["compose.resolved.run.yml"]
    let m = (read-compose-manifest $tmp)
    let last_input = ($m.applied_inputs | last)
    let results_main = [
        (assert-truthy ($last_input == "inputs/runner-ci.yml") "applied_inputs ends with runner-ci.yml")
        (assert-eq ($m.applied_inputs | length) 4 "applied_inputs has 4 entries")
        (assert-eq $m.resolved_files ["compose.resolved.run.yml"] "resolved_files with runner")
    ]
    let tmp2 = (make-fixture {exec.yml: "a", sender.yml: "b"} false)
    write-compose-manifest $tmp2 "sid" ["exec.yml" "sender.yml"] "" []
    let m2 = (read-compose-manifest $tmp2)
    let result_hash = (assert-truthy ($m.stack_def_sha256 != $m2.stack_def_sha256)
        "def hash differs when runner_fname present vs absent")
    rm -rf $tmp
    rm -rf $tmp2
    $results_main | append $result_hash
}

def main [] {
    test-log "=== compose-manifest Tests ==="
    let results = (
        (test-writer-roundtrip)
        | append (test-stack-def-hash-stable-across-env-change)
        | append (test-stack-env-hash-empty-when-missing)
        | append (test-stack-def-hash-changes-when-overlay-changes)
        | append (test-runner-fname-appends-to-applied-inputs)
    ) | flatten
    run-suite "services/compose-manifest" $SUITE_PATH $results
}
