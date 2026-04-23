# Tests for finalize-run and write-final-verdict.
# Run: nu scripts/tests/run/finalize.nu
# Returns exit 0 on all pass, exit 1 with details on failure.

const SUITE_PATH = path self

use ../../lib/run/finalize.nu [finalize-run]
use ../../lib/run/metadata.nu [write-final-verdict utc-now]
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

# ---- write-final-verdict tests ----

def test-write-final-verdict-pass-shape [] {
    test-log "\n[test-write-final-verdict-pass-shape]"
    let tmp = (^mktemp -d | str trim)
    mkdir ($tmp | path join "meta")
    let base_rec = {status: "passed", exit_code: 0}
    let final_rec = {status: "passed", exit_code: 0}
    write-final-verdict $tmp "after-down" $base_rec $final_rec []
    let path = ($tmp | path join "meta/final-verdict.json")
    let exists = ($path | path exists)
    let doc = if $exists { open $path } else { {} }
    let base = ($doc.base? | default {status: "", exit_code: (-99)})
    let final = ($doc.final? | default {status: "", exit_code: (-99)})
    ^rm -rf $tmp
    [
        (assert-truthy $exists "meta/final-verdict.json created")
        (assert-eq ($doc.schema_version? | default 0) 2
            "schema_version is 2")
        (assert-eq ($doc.stage? | default "") "after-down"
            "stage field preserved")
        (assert-eq $base.status "passed"
            "base.status is passed")
        (assert-eq $base.exit_code 0
            "base.exit_code is 0")
        (assert-eq $final.status "passed"
            "final.status is passed")
        (assert-eq $final.exit_code 0
            "final.exit_code is 0")
        (assert-eq ($doc.validators? | default null) []
            "validators is empty list")
    ]
}

def test-write-final-verdict-fail-shape [] {
    test-log "\n[test-write-final-verdict-fail-shape]"
    let tmp = (^mktemp -d | str trim)
    mkdir ($tmp | path join "meta")
    write-final-verdict $tmp "after-cypress" {status: "failed", exit_code: 7} {status: "failed", exit_code: 7} []
    let path = ($tmp | path join "meta/final-verdict.json")
    let doc = if ($path | path exists) { open $path } else { {} }
    let base = ($doc.base? | default {status: "", exit_code: (-99)})
    let final = ($doc.final? | default {status: "", exit_code: (-99)})
    ^rm -rf $tmp
    [
        (assert-eq ($doc.stage? | default "") "after-cypress"
            "stage is after-cypress")
        (assert-eq $base.exit_code 7
            "base.exit_code preserves nonstandard code")
        (assert-eq $final.exit_code 7
            "final.exit_code preserves nonstandard code")
    ]
}

def test-write-final-verdict-override-shape [] {
    test-log "\n[test-write-final-verdict-override-shape]"
    let tmp = (^mktemp -d | str trim)
    mkdir ($tmp | path join "meta")
    # base passed/0, final failed/2 (validator override with custom exit code)
    write-final-verdict $tmp "after-down" {status: "passed", exit_code: 0} {status: "failed", exit_code: 2} ["ocm-validator"]
    let path = ($tmp | path join "meta/final-verdict.json")
    let doc = if ($path | path exists) { open $path } else { {} }
    let base = ($doc.base? | default {status: "", exit_code: (-99)})
    let final = ($doc.final? | default {status: "", exit_code: (-99)})
    ^rm -rf $tmp
    [
        (assert-eq $base.status "passed"
            "base.status tracks original cypress")
        (assert-eq $base.exit_code 0
            "base.exit_code tracks original cypress")
        (assert-eq $final.status "failed"
            "final.status reflects override")
        (assert-eq $final.exit_code 2
            "final.exit_code carries explicit override code")
        (assert-eq ($doc.validators? | default []) ["ocm-validator"]
            "validator name recorded")
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
    let verdict_path = ($tmp | path join "meta/final-verdict.json")
    let run_path = ($tmp | path join "meta/run.json")
    let verdict = if ($verdict_path | path exists) { open $verdict_path } else { {} }
    let run = if ($run_path | path exists) { open $run_path } else { {} }
    let final_rec = ($verdict.final? | default {status: "", exit_code: (-99)})
    let base_rec = ($verdict.base? | default {status: "", exit_code: (-99)})
    ^rm -rf $tmp
    [
        (assert-eq $exit_code 0
            "finalize-run returns 0 when Cypress passed")
        (assert-eq $final_rec.status "passed"
            "final-verdict.json final.status=passed")
        (assert-eq $final_rec.exit_code 0
            "final-verdict.json final.exit_code=0")
        (assert-eq $base_rec.status "passed"
            "final-verdict.json base.status=passed")
        (assert-eq $base_rec.exit_code 0
            "final-verdict.json base.exit_code=0")
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
    let verdict_path = ($tmp | path join "meta/final-verdict.json")
    let run_path = ($tmp | path join "meta/run.json")
    let verdict = if ($verdict_path | path exists) { open $verdict_path } else { {} }
    let run = if ($run_path | path exists) { open $run_path } else { {} }
    let final_rec = ($verdict.final? | default {status: "", exit_code: (-99)})
    let base_rec = ($verdict.base? | default {status: "", exit_code: (-99)})
    ^rm -rf $tmp
    [
        (assert-eq $exit_code 1
            "finalize-run returns 1 when Cypress failed with exit 1")
        (assert-eq $final_rec.status "failed"
            "final-verdict.json final.status=failed")
        (assert-eq $final_rec.exit_code 1
            "final-verdict.json final.exit_code=1")
        (assert-eq $base_rec.exit_code 1
            "final-verdict.json base.exit_code=1")
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
    let verdict_path = ($tmp | path join "meta/final-verdict.json")
    let run_path = ($tmp | path join "meta/run.json")
    let verdict = if ($verdict_path | path exists) { open $verdict_path } else { {} }
    let run = if ($run_path | path exists) { open $run_path } else { {} }
    let final_rec = ($verdict.final? | default {status: "", exit_code: (-99)})
    let base_rec = ($verdict.base? | default {status: "", exit_code: (-99)})
    ^rm -rf $tmp
    [
        (assert-eq $exit_code 7
            "cypress exit 7 returned unchanged when no validator override")
        (assert-eq $base_rec.exit_code 7
            "final-verdict.json base.exit_code=7")
        (assert-eq $final_rec.exit_code 7
            "final-verdict.json final.exit_code=7 preserved")
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
    let verdict_path = ($tmp | path join "meta/final-verdict.json")
    let run_path = ($tmp | path join "meta/run.json")
    let verdict = if ($verdict_path | path exists) { open $verdict_path } else { {} }
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
    let verdict_path = ($tmp | path join "meta/final-verdict.json")
    let run_path = ($tmp | path join "meta/run.json")
    let verdict = if ($verdict_path | path exists) { open $verdict_path } else { {} }
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
    let verdict_path = ($tmp | path join "meta/final-verdict.json")
    let result_path = ($tmp | path join "meta/result.json")
    let verdict_exists = ($verdict_path | path exists)
    let result_exists = ($result_path | path exists)
    let run = if ($run_path | path exists) { open $run_path } else { {} }
    ^rm -rf $tmp
    [
        (assert-eq $exit_code 0
            "auto-dispatch no-op: cypress pass -> exit 0")
        (assert-eq ($run.status? | default "") "passed"
            "auto-dispatch no-op: run.json status=passed")
        (assert-truthy $verdict_exists
            "auto-dispatch writes final-verdict.json")
        (assert-truthy $result_exists
            "auto-dispatch writes result.json via write-terminal-outcome")
    ]
}

# Suite fields pass through to run.json / result.json unchanged.
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
    let result_path = ($tmp | path join "meta/result.json")
    let run = if ($run_path | path exists) { open $run_path } else { {} }
    let result = if ($result_path | path exists) { open $result_path } else { {} }
    ^rm -rf $tmp
    [
        (assert-eq ($run.suite_id? | default "") $sid
            "run.json has suite_id")
        (assert-eq ($run.suite_kind? | default "") "suite"
            "run.json has suite_kind")
        (assert-eq ($result.suite_id? | default "") $sid
            "result.json has suite_id")
        (assert-eq ($result.suite_kind? | default "") "suite"
            "result.json has suite_kind")
    ]
}

def main [] {
    test-log "=== Finalize Run + Final Verdict Tests ==="
    let results = (
        (test-write-final-verdict-pass-shape)
        | append (test-write-final-verdict-fail-shape)
        | append (test-write-final-verdict-override-shape)
        | append (test-finalize-run-pass-no-override)
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
