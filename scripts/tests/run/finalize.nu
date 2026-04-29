# Tests for finalize-run.
# Run: nu scripts/tests/run/finalize.nu
# Returns exit 0 on all pass, exit 1 with details on failure.

const SUITE_PATH = path self

use ../../lib/run/finalize.nu [finalize-run]
use ../../lib/run/metadata.nu [utc-now]
use ../../lib/tests/assert.nu *
use ../../lib/tests/runner.nu [run-suite]

# Paths assume repo-root cwd (see file header).
# Wave 4 split the fat domain routers into per-verb files. The whole verb
# file now IS the block previously extracted between def-markers - so we
# read each verb file directly and assert against its full text.
def test-domain-sources-route-through-finalize-run [] {
    test-log "\n[test-domain-sources-route-through-finalize-run]"
    let want_use = "use ../../lib/run/finalize.nu [finalize-run]"
    let up_run_path = "scripts/domains/services/up-run.nu"
    let test_run_path = "scripts/domains/test/cypress-run.nu"
    let up_run_src = (open --raw $up_run_path)
    let test_run_src = (open --raw $test_run_path)
    [
        (assert-truthy ($up_run_src | str contains $want_use)
            "services/up-run.nu imports finalize-run from ../../lib/run/finalize.nu")
        (assert-truthy ($up_run_src | str contains "finalize-run")
            "services up run body calls finalize-run")
        (assert-truthy ($up_run_src | str contains "after-down")
            "services up run uses after-down for teardown finalization path")
        (assert-truthy ($test_run_src | str contains $want_use)
            "test/cypress-run.nu imports finalize-run from ../../lib/run/finalize.nu")
        (assert-truthy ($test_run_src | str contains "finalize-run")
            "test run body calls finalize-run")
        (assert-truthy ($test_run_src | str contains "after-cypress")
            "test run uses after-cypress stage for finalization"),
    ]
}

# ---- finalize-run tests ----

def test-finalize-run-pass-no-override [] {
    test-log "\n[test-finalize-run-pass-no-override]"
    let tmp = (^mktemp -d | str trim)
    mkdir ($tmp | path join "meta")
    let ts = (utc-now)
    let no_op_report = {validators: [], override_outcome: null, override_exit_code: null, notes: []}
    let exit_code = (finalize-run $tmp "exec-fv-001" "login__nc-v34"
        "cell-login-nc-v34" $ts $ts "stack-fv-001" 0 "after-down" null
        --validator-report $no_op_report)
    let result_path = ($tmp | path join "meta/result.v1.json")
    let run_path = ($tmp | path join "meta/run.json")
    let result = if ($result_path | path exists) { open $result_path } else { {} }
    let verdict = ($result.verdict? | default {})
    let run = if ($run_path | path exists) { open $run_path } else { {} }
    let final_rec = ($verdict.final? | default {status: "", exit_code: (-99)})
    let base_rec = ($verdict.base? | default {status: "", exit_code: (-99)})
    ^rm -rf $tmp
    [
        (assert-eq $exit_code 0
            "finalize-run returns 0 when Cypress passed")
        (assert-eq $final_rec.status "passed"
            "result.v1.json verdict.final.status=passed")
        (assert-eq $final_rec.exit_code 0
            "result.v1.json verdict.final.exit_code=0")
        (assert-eq $base_rec.status "passed"
            "result.v1.json verdict.base.status=passed")
        (assert-eq $base_rec.exit_code 0
            "result.v1.json verdict.base.exit_code=0")
        (assert-eq ($run.status? | default "") "passed"
            "run.json status=passed")
        (assert-eq ($run.exit_code? | default (-99)) 0
            "run.json exit_code=0")
    ]
}

def test-finalize-run-fail-no-override [] {
    test-log "\n[test-finalize-run-fail-no-override]"
    let tmp = (^mktemp -d | str trim)
    mkdir ($tmp | path join "meta")
    let ts = (utc-now)
    let no_op_report = {validators: [], override_outcome: null, override_exit_code: null, notes: []}
    let exit_code = (finalize-run $tmp "exec-fv-002" "login__nc-v34"
        "cell-login-nc-v34" $ts $ts "stack-fv-002" 1 "after-down" null
        --validator-report $no_op_report)
    let result_path = ($tmp | path join "meta/result.v1.json")
    let run_path = ($tmp | path join "meta/run.json")
    let result = if ($result_path | path exists) { open $result_path } else { {} }
    let verdict = ($result.verdict? | default {})
    let run = if ($run_path | path exists) { open $run_path } else { {} }
    let final_rec = ($verdict.final? | default {status: "", exit_code: (-99)})
    let base_rec = ($verdict.base? | default {status: "", exit_code: (-99)})
    ^rm -rf $tmp
    [
        (assert-eq $exit_code 1
            "finalize-run returns 1 when Cypress failed with exit 1")
        (assert-eq $final_rec.status "failed"
            "result.v1.json verdict.final.status=failed")
        (assert-eq $final_rec.exit_code 1
            "result.v1.json verdict.final.exit_code=1")
        (assert-eq $base_rec.exit_code 1
            "result.v1.json verdict.base.exit_code=1")
        (assert-eq ($run.exit_code? | default 0) 1
            "run.json exit_code=1")
    ]
}

# Cypress can exit with nonstandard codes (e.g. 7); those must be preserved exactly.
def test-finalize-run-preserves-nonstandard-cypress-exit [] {
    test-log "\n[test-finalize-run-preserves-nonstandard-cypress-exit]"
    let tmp = (^mktemp -d | str trim)
    mkdir ($tmp | path join "meta")
    let ts = (utc-now)
    let no_op_report = {validators: [], override_outcome: null, override_exit_code: null, notes: []}
    let exit_code = (finalize-run $tmp "exec-fv-exit7" "login__nc-v34"
        "cell-login-nc-v34" $ts $ts "stack-fv-exit7" 7 "after-down" null
        --validator-report $no_op_report)
    let result_path = ($tmp | path join "meta/result.v1.json")
    let run_path = ($tmp | path join "meta/run.json")
    let result = if ($result_path | path exists) { open $result_path } else { {} }
    let verdict = ($result.verdict? | default {})
    let run = if ($run_path | path exists) { open $run_path } else { {} }
    let final_rec = ($verdict.final? | default {status: "", exit_code: (-99)})
    let base_rec = ($verdict.base? | default {status: "", exit_code: (-99)})
    ^rm -rf $tmp
    [
        (assert-eq $exit_code 7
            "cypress exit 7 returned unchanged when no validator override")
        (assert-eq $base_rec.exit_code 7
            "result.v1.json verdict.base.exit_code=7")
        (assert-eq $final_rec.exit_code 7
            "result.v1.json verdict.final.exit_code=7 preserved")
        (assert-eq ($run.exit_code? | default (-99)) 7
            "run.json exit_code=7 preserved")
    ]
}

# Validator overrides fail->pass with explicit exit code.
def test-finalize-run-validator-override-fail-to-pass [] {
    test-log "\n[test-finalize-run-validator-override-fail-to-pass]"
    let tmp = (^mktemp -d | str trim)
    mkdir ($tmp | path join "meta")
    let ts = (utc-now)
    let override_report = {
        validators: ["mock-validator"],
        override_outcome: "passed",
        override_exit_code: null,  # derive from status -> 0
        notes: ["mock: expected failure cleared"],
    }
    let exit_code = (finalize-run $tmp "exec-fv-003" "login__nc-v34"
        "cell-login-nc-v34" $ts $ts "stack-fv-003" 1 "after-down" null
        --validator-report $override_report)
    let result_path = ($tmp | path join "meta/result.v1.json")
    let run_path = ($tmp | path join "meta/run.json")
    let result = if ($result_path | path exists) { open $result_path } else { {} }
    let verdict = ($result.verdict? | default {})
    let run = if ($run_path | path exists) { open $run_path } else { {} }
    let final_rec = ($verdict.final? | default {status: "", exit_code: (-99)})
    let base_rec = ($verdict.base? | default {status: "", exit_code: (-99)})
    ^rm -rf $tmp
    [
        (assert-eq $exit_code 0
            "validator override fail->pass yields exit 0")
        (assert-eq $base_rec.status "failed"
            "base still records cypress was failed")
        (assert-eq $base_rec.exit_code 1
            "base.exit_code still carries cypress exit 1")
        (assert-eq $final_rec.status "passed"
            "final.status reflects validator override")
        (assert-eq $final_rec.exit_code 0
            "final.exit_code derived from override status (passed -> 0)")
        (assert-eq ($verdict.validators? | default []) ["mock-validator"]
            "validator name recorded")
        (assert-eq ($run.status? | default "") "passed"
            "run.json status follows final verdict")
        (assert-eq ($run.exit_code? | default (-99)) 0
            "run.json exit_code=0 after override")
    ]
}

# Validator overrides pass->fail; final must be failed with explicit exit code.
def test-finalize-run-validator-override-pass-to-fail [] {
    test-log "\n[test-finalize-run-validator-override-pass-to-fail]"
    let tmp = (^mktemp -d | str trim)
    mkdir ($tmp | path join "meta")
    let ts = (utc-now)
    let override_report = {
        validators: ["ocm-validator"],
        override_outcome: "failed",
        override_exit_code: 2,  # explicit non-1 code to verify it is respected
        notes: ["OCM endpoint check failed after Cypress passed"],
    }
    let exit_code = (finalize-run $tmp "exec-fv-p2f" "login__nc-v34"
        "cell-login-nc-v34" $ts $ts "stack-fv-p2f" 0 "after-down" null
        --validator-report $override_report)
    let result_path = ($tmp | path join "meta/result.v1.json")
    let run_path = ($tmp | path join "meta/run.json")
    let result = if ($result_path | path exists) { open $result_path } else { {} }
    let verdict = ($result.verdict? | default {})
    let run = if ($run_path | path exists) { open $run_path } else { {} }
    let final_rec = ($verdict.final? | default {status: "", exit_code: (-99)})
    let base_rec = ($verdict.base? | default {status: "", exit_code: (-99)})
    ^rm -rf $tmp
    [
        (assert-eq $exit_code 2
            "validator override pass->fail with explicit exit_code=2 returns 2")
        (assert-eq $base_rec.status "passed"
            "base.status tracks original cypress (passed)")
        (assert-eq $base_rec.exit_code 0
            "base.exit_code tracks original cypress (0)")
        (assert-eq $final_rec.status "failed"
            "final.status reflects validator override (failed)")
        (assert-eq $final_rec.exit_code 2
            "final.exit_code carries explicit override exit code 2")
        (assert-eq ($verdict.validators? | default []) ["ocm-validator"]
            "validator name recorded")
        (assert-eq ($run.status? | default "") "failed"
            "run.json status=failed after override")
        (assert-eq ($run.exit_code? | default (-99)) 2
            "run.json exit_code=2 after override")
    ]
}

# Auto-dispatch (no injected report): no-op preserves Cypress outcome exactly.
def test-finalize-run-auto-dispatch-no-op [] {
    test-log "\n[test-finalize-run-auto-dispatch-no-op]"
    let tmp = (^mktemp -d | str trim)
    mkdir ($tmp | path join "meta")
    let ts = (utc-now)
    let exit_code = (finalize-run $tmp "exec-fv-004" "login__nc-v34"
        "cell-login-nc-v34" $ts $ts "stack-fv-004" 0 "after-down")
    let run_path = ($tmp | path join "meta/run.json")
    let result_path = ($tmp | path join "meta/result.v1.json")
    let result_exists = ($result_path | path exists)
    let result_verdict_present = if $result_exists {
        ((open $result_path) | columns | any {|c| $c == "verdict"})
    } else {
        false
    }
    let run = if ($run_path | path exists) { open $run_path } else { {} }
    ^rm -rf $tmp
    [
        (assert-eq $exit_code 0
            "auto-dispatch no-op: cypress pass -> exit 0")
        (assert-eq ($run.status? | default "") "passed"
            "auto-dispatch no-op: run.json status=passed")
        (assert-truthy $result_exists
            "auto-dispatch writes result.v1.json")
        (assert-truthy $result_verdict_present
            "auto-dispatch result.v1.json includes verdict block")
    ]
}

# Suite fields pass through to run.json / result.v1.json unchanged.
def test-finalize-run-suite-fields-passthrough [] {
    test-log "\n[test-finalize-run-suite-fields-passthrough]"
    let tmp = (^mktemp -d | str trim)
    mkdir ($tmp | path join "meta")
    let ts = (utc-now)
    let sid = "20260101t120000-aabbccdd"
    let no_op_report = {validators: [], override_outcome: null, override_exit_code: null, notes: []}
    let _exit_code = (finalize-run $tmp "exec-fv-005" "login__nc-v34"
        "cell-login-nc-v34" $ts $ts "stack-fv-005" 0 "after-down" null
        --suite-id $sid --suite-kind "suite"
        --validator-report $no_op_report)
    let run_path = ($tmp | path join "meta/run.json")
    let result_path = ($tmp | path join "meta/result.v1.json")
    let run = if ($run_path | path exists) { open $run_path } else { {} }
    let result = if ($result_path | path exists) { open $result_path } else { {} }
    ^rm -rf $tmp
    [
        (assert-eq ($run.suite_id? | default "") $sid
            "run.json has suite_id")
        (assert-eq ($run.suite_kind? | default "") "suite"
            "run.json has suite_kind")
        (assert-eq ($result.suite_id? | default "") $sid
            "result.v1.json has suite_id")
        (assert-eq ($result.suite_kind? | default "") "suite"
            "result.v1.json has suite_kind")
    ]
}

def main [] {
    test-log "=== Finalize Run Tests ==="
    let results = (
        (test-finalize-run-pass-no-override)
        | append (test-finalize-run-fail-no-override)
        | append (test-finalize-run-preserves-nonstandard-cypress-exit)
        | append (test-finalize-run-validator-override-fail-to-pass)
        | append (test-finalize-run-validator-override-pass-to-fail)
        | append (test-finalize-run-auto-dispatch-no-op)
        | append (test-finalize-run-suite-fields-passthrough)
        | append (test-domain-sources-route-through-finalize-run)
    ) | flatten
    run-suite "run/finalize" $SUITE_PATH $results
}
