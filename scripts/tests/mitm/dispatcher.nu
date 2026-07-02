# Tests for validator-dispatcher: dispatch-validators and merge-validator-reports.
# Run: nu scripts/tests/mitm/dispatcher.nu
# Returns exit 0 on all pass, exit 1 with details on failure.

const SUITE_PATH = path self

use ../../lib/mitm/validator-dispatcher.nu [dispatch-validators merge-validator-reports]
use ../../lib/tests/assert.nu *
use ../../lib/tests/runner.nu [run-suite]
use ../../lib/tests/fixtures.nu [with-tmp-dir]

# ---- dispatch-validators tests ----

# after-down stage returns noop report (no validators).
def test-dispatch-after-down-noop [] {
    test-log "\n[test-dispatch-after-down-noop]"
    with-tmp-dir {|tmp|
        let report = (dispatch-validators $tmp "after-down" "passed")
        [
            (assert-eq $report.validators [] "after-down: validators empty")
            (assert-null $report.override_outcome "after-down: override_outcome null")
            (assert-null $report.override_exit_code "after-down: override_exit_code null")
            (assert-eq $report.notes [] "after-down: notes empty")
        ]
    }
}

# after-cypress stage returns noop report (no validators).
def test-dispatch-after-cypress-noop [] {
    test-log "\n[test-dispatch-after-cypress-noop]"
    with-tmp-dir {|tmp|
        let report = (dispatch-validators $tmp "after-cypress" "passed")
        [
            (assert-eq $report.validators [] "after-cypress: validators empty")
            (assert-null $report.override_outcome "after-cypress: override_outcome null")
            (assert-null $report.override_exit_code "after-cypress: override_exit_code null")
            (assert-eq $report.notes [] "after-cypress: notes empty")
        ]
    }
}

# Unknown stage returns noop report.
def test-dispatch-unknown-stage-noop [] {
    test-log "\n[test-dispatch-unknown-stage-noop]"
    let tmp = (^mktemp -d | str trim)
    let report = (dispatch-validators $tmp "unknown-stage" "passed")
    ^rm -rf $tmp
    [
        (assert-eq $report.validators [] "unknown stage: validators empty")
        (assert-null $report.override_outcome "unknown stage: override null")
    ]
}

# ---- merge-validator-reports tests ----

# Failed override wins over a passed override in the same batch.
def test-merge-failed-wins-over-pass [] {
    test-log "\n[test-merge-failed-wins-over-pass]"
    let reports = [
        {validators: ["v-fail"], override_outcome: "failed", override_exit_code: null, notes: ["fail note"]},
        {validators: ["v-pass"], override_outcome: "passed", override_exit_code: null, notes: ["pass note"]},
    ]
    let merged = (merge-validator-reports $reports "passed")
    [
        (assert-eq $merged.override_outcome "failed"
            "failed override wins when both failed and passed overrides present")
        (assert-eq $merged.override_exit_code 1
            "failed override with no explicit code derives exit code 1")
        (assert-eq $merged.validators ["v-fail" "v-pass"]
            "validator names concatenated")
        (assert-eq $merged.notes ["fail note" "pass note"]
            "notes concatenated")
    ]
}

# Pass override flips a failed base when no failed override present.
def test-merge-pass-override-flips-failed-base [] {
    test-log "\n[test-merge-pass-override-flips-failed-base]"
    let reports = [
        {validators: ["v-pass"], override_outcome: "passed", override_exit_code: null, notes: ["expected failure cleared"]},
    ]
    let merged = (merge-validator-reports $reports "failed")
    [
        (assert-eq $merged.override_outcome "passed"
            "pass override flips failed base when no failed override")
        (assert-eq $merged.override_exit_code 0
            "pass override flipping failed base with no explicit code derives exit code 0")
    ]
}

# Pass override does NOT flip a passed base (no override needed).
def test-merge-pass-override-no-flip-on-passed-base [] {
    test-log "\n[test-merge-pass-override-no-flip-on-passed-base]"
    let reports = [
        {validators: ["v-pass"], override_outcome: "passed", override_exit_code: null, notes: []},
    ]
    let merged = (merge-validator-reports $reports "passed")
    [
        (assert-null $merged.override_outcome
            "pass override does not set override when base is already passed")
    ]
}

# Validator names and notes are concatenated across multiple reports.
def test-merge-concat-names-and-notes [] {
    test-log "\n[test-merge-concat-names-and-notes]"
    let reports = [
        {validators: ["alpha"], override_outcome: null, override_exit_code: null, notes: ["note-a"]},
        {validators: ["beta" "gamma"], override_outcome: null, override_exit_code: null, notes: ["note-b"]},
    ]
    let merged = (merge-validator-reports $reports "passed")
    [
        (assert-eq $merged.validators ["alpha" "beta" "gamma"]
            "validator names concatenated from all reports")
        (assert-eq $merged.notes ["note-a" "note-b"]
            "notes concatenated from all reports")
        (assert-null $merged.override_outcome
            "override is null when no report sets an override")
    ]
}

# Explicit exit code from winning failed override is preserved.
def test-merge-failed-override-explicit-exit-code [] {
    test-log "\n[test-merge-failed-override-explicit-exit-code]"
    let reports = [
        {validators: ["v-fail"], override_outcome: "failed", override_exit_code: 3, notes: []},
    ]
    let merged = (merge-validator-reports $reports "passed")
    [
        (assert-eq $merged.override_outcome "failed" "override is failed")
        (assert-eq $merged.override_exit_code 3
            "explicit exit code from failed override is preserved")
    ]
}

# dispatch-validators ignores artifacts_base; stage-only noop.
def test-dispatch-ignores-artifacts-base-noop [] {
    test-log "\n[test-dispatch-ignores-artifacts-base-noop]"
    with-tmp-dir {|tmp|
        mkdir ($tmp | path join "meta")
        {cell: "value"} | to json | save ($tmp | path join "meta/cell.json")
        let report = (dispatch-validators $tmp "after-down" "failed")
        [
            (assert-eq $report.validators [] "artifacts_base ignored: validators empty")
            (assert-null $report.override_outcome "artifacts_base ignored: override_outcome null")
            (assert-null $report.override_exit_code "artifacts_base ignored: override_exit_code null")
            (assert-eq $report.notes [] "artifacts_base ignored: notes empty")
        ]
    }
}

# Mixed failed overrides (null first, explicit second): explicit code wins.
def test-merge-failed-explicit-wins-null-first [] {
    test-log "\n[test-merge-failed-explicit-wins-null-first]"
    let reports = [
        {validators: ["v-null"], override_outcome: "failed", override_exit_code: null, notes: []},
        {validators: ["v-explicit"], override_outcome: "failed", override_exit_code: 3, notes: []},
    ]
    let merged = (merge-validator-reports $reports "passed")
    [
        (assert-eq $merged.override_outcome "failed" "failed override outcome")
        (assert-eq $merged.override_exit_code 3
            "explicit code 3 wins over null when null report is listed first")
    ]
}

# Mixed failed overrides (explicit first, null second): explicit code wins.
def test-merge-failed-explicit-wins-explicit-first [] {
    test-log "\n[test-merge-failed-explicit-wins-explicit-first]"
    let reports = [
        {validators: ["v-explicit"], override_outcome: "failed", override_exit_code: 3, notes: []},
        {validators: ["v-null"], override_outcome: "failed", override_exit_code: null, notes: []},
    ]
    let merged = (merge-validator-reports $reports "passed")
    [
        (assert-eq $merged.override_outcome "failed" "failed override outcome")
        (assert-eq $merged.override_exit_code 3
            "explicit code 3 wins over null when explicit report is listed first")
    ]
}

# Mixed passed overrides on failed base (null first, explicit second): explicit code wins.
def test-merge-passed-explicit-wins-null-first [] {
    test-log "\n[test-merge-passed-explicit-wins-null-first]"
    let reports = [
        {validators: ["v-null"], override_outcome: "passed", override_exit_code: null, notes: []},
        {validators: ["v-explicit"], override_outcome: "passed", override_exit_code: 5, notes: []},
    ]
    let merged = (merge-validator-reports $reports "failed")
    [
        (assert-eq $merged.override_outcome "passed" "passed override outcome on failed base")
        (assert-eq $merged.override_exit_code 5
            "explicit code 5 wins over derived 0 when null report is listed first")
    ]
}

# Mixed passed overrides on failed base (explicit first, null second): explicit code wins.
def test-merge-passed-explicit-wins-explicit-first [] {
    test-log "\n[test-merge-passed-explicit-wins-explicit-first]"
    let reports = [
        {validators: ["v-explicit"], override_outcome: "passed", override_exit_code: 5, notes: []},
        {validators: ["v-null"], override_outcome: "passed", override_exit_code: null, notes: []},
    ]
    let merged = (merge-validator-reports $reports "failed")
    [
        (assert-eq $merged.override_outcome "passed" "passed override outcome on failed base")
        (assert-eq $merged.override_exit_code 5
            "explicit code 5 wins over derived 0 when explicit report is listed first")
    ]
}

def main [] {
    test-log "=== Validator Dispatcher + Merge Tests ==="
    let results = (
        (test-dispatch-after-down-noop)
        | append (test-dispatch-after-cypress-noop)
        | append (test-dispatch-unknown-stage-noop)
        | append (test-dispatch-ignores-artifacts-base-noop)
        | append (test-merge-failed-wins-over-pass)
        | append (test-merge-pass-override-flips-failed-base)
        | append (test-merge-pass-override-no-flip-on-passed-base)
        | append (test-merge-concat-names-and-notes)
        | append (test-merge-failed-override-explicit-exit-code)
        | append (test-merge-failed-explicit-wins-null-first)
        | append (test-merge-failed-explicit-wins-explicit-first)
        | append (test-merge-passed-explicit-wins-null-first)
        | append (test-merge-passed-explicit-wins-explicit-first)
    ) | flatten
    run-suite "mitm/dispatcher" $SUITE_PATH $results
}
