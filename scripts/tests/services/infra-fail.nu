# Tests for scripts/lib/services/infra-fail.nu with-infra-fail-cleanup --suite-record.
# Run: nu scripts/tests/services/infra-fail.nu

const SUITE_PATH = path self

use ../../lib/services/infra-fail.nu [with-infra-fail-cleanup]
use ../../lib/time/utc.nu [utc-now]
use ../../lib/tests/assert.nu *
use ../../lib/tests/runner.nu [run-suite]

# Build a minimal ctx record that satisfies write-terminal-outcome and lifecycle helpers.
def fixture-ctx [artifacts_base: string] {
    let ts = (utc-now)
    {
        artifacts_base: $artifacts_base,
        execution_id: "20260101t120000-aabbccdd",
        cell: {
            cell_id: "login__nextcloud-v34",
            artifact_name: "cell-login-nextcloud-v34",
            flow_id: "login",
            pair: "nextcloud-v34",
        },
        started_at: $ts,
        stack_id: "ocmts-test-stack",
        images: null,
        suite_id: "",
        suite_kind: "single",
    }
}

# --suite-record closure is called with {status, exit_code} before publish.
def test-suite-record-closure-called-on-failure [] {
    test-log "\n[test-suite-record-closure-called-on-failure]"
    let tmp = (^mktemp -d | str trim)
    mkdir ($tmp | path join "meta")
    let ctx = (fixture-ctx $tmp)
    let marker = ($tmp | path join "suite_record_called")

    let result = (try {
        (with-infra-fail-cleanup $ctx "test-phase" {
            error make {msg: "simulated infra failure"}
        } --suite-record {|r|
            $r.status | save --force $marker
        })
        "no-error"
    } catch {|e| "caught"})

    let was_called = ($marker | path exists)
    let recorded_status = if $was_called { open --raw $marker | str trim } else { "" }
    ^rm -rf $tmp
    [
        (assert-eq $result "caught"
            "with-infra-fail-cleanup re-throws after catch")
        (assert-truthy $was_called
            "--suite-record closure was invoked on failure")
        (assert-eq $recorded_status "infra-failed"
            "--suite-record closure receives status=infra-failed")
    ]
}

# Without --suite-record, default behavior is no-op (no closure called).
def test-suite-record-default-noop [] {
    test-log "\n[test-suite-record-default-noop]"
    let tmp = (^mktemp -d | str trim)
    mkdir ($tmp | path join "meta")
    let ctx = (fixture-ctx $tmp)

    # Should not error due to missing suite_record; just re-throws the action error.
    let result = (try {
        (with-infra-fail-cleanup $ctx "test-phase" {
            error make {msg: "simulated infra failure"}
        })
        "no-error"
    } catch {|e| "caught"})

    ^rm -rf $tmp
    [
        (assert-eq $result "caught"
            "default (no --suite-record) still re-throws on failure")
    ]
}

# On success the action result is returned and closure is never called.
def test-suite-record-not-called-on-success [] {
    test-log "\n[test-suite-record-not-called-on-success]"
    let tmp = (^mktemp -d | str trim)
    mkdir ($tmp | path join "meta")
    let ctx = (fixture-ctx $tmp)
    let marker = ($tmp | path join "suite_record_called")

    (with-infra-fail-cleanup $ctx "test-phase" {
        "action succeeded"
    } --suite-record {|r|
        "called" | save --force $marker
    })

    let was_called = ($marker | path exists)
    ^rm -rf $tmp
    [
        (assert-truthy (not $was_called)
            "--suite-record closure is NOT called when action succeeds")
    ]
}

def main [] {
    test-log "=== services/infra-fail tests ==="
    let results = (
        (test-suite-record-closure-called-on-failure)
        | append (test-suite-record-default-noop)
        | append (test-suite-record-not-called-on-success)
    ) | flatten
    run-suite "services/infra-fail" $SUITE_PATH $results
}
