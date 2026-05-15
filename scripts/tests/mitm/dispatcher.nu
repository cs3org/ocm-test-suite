# Tests for validator-dispatcher: dispatch-validators and merge-validator-reports.
# Run: nu scripts/tests/mitm/dispatcher.nu
# Returns exit 0 on all pass, exit 1 with details on failure.

const SUITE_PATH = path self

use ../../lib/mitm/validator-dispatcher.nu [dispatch-validators merge-validator-reports]
use ../../lib/tests/assert.nu *
use ../../lib/tests/runner.nu [run-suite]
use ../../lib/tests/fixtures.nu [with-tmp-dir]

# ---- dispatch-validators tests ----

# after-down with flow_id="code-flow" (stub) returns noop merged report.
def test-dispatch-after-down-code-flow-stub [] {
    test-log "\n[test-dispatch-after-down-code-flow-stub]"
    with-tmp-dir {|tmp|
        mkdir ($tmp | path join "meta")
        {flow_id: "code-flow"} | save ($tmp | path join "meta/cell.json")
        let report = (dispatch-validators $tmp "after-down" "passed")
        [
            (assert-eq $report.validators [] "validators is empty (stub)")
            (assert-null $report.override_outcome "override_outcome is null (stub)")
            (assert-null $report.override_exit_code "override_exit_code is null (stub)")
            (assert-eq $report.notes [] "notes is empty (stub)")
        ]
    }
}

# after-down with unknown flow_id returns noop report (no validators).
def test-dispatch-after-down-unknown-flow [] {
    test-log "\n[test-dispatch-after-down-unknown-flow]"
    let tmp = (^mktemp -d | str trim)
    mkdir ($tmp | path join "meta")
    {flow_id: "unknown-flow"} | save ($tmp | path join "meta/cell.json")
    let report = (dispatch-validators $tmp "after-down" "passed")
    ^rm -rf $tmp
    [
        (assert-eq $report.validators [] "validators is empty for unknown flow")
        (assert-null $report.override_outcome "override_outcome is null for unknown flow")
    ]
}

# after-down with no cell.json returns noop report.
def test-dispatch-after-down-no-cell-json [] {
    test-log "\n[test-dispatch-after-down-no-cell-json]"
    with-tmp-dir {|tmp|
        mkdir ($tmp | path join "meta")
        let report = (dispatch-validators $tmp "after-down" "passed")
        [
            (assert-eq $report.validators [] "validators is empty when no cell.json")
            (assert-null $report.override_outcome "override_outcome is null when no cell.json")
        ]
    }
}

# after-cypress always returns noop report regardless of flow.
def test-dispatch-after-cypress-noop [] {
    test-log "\n[test-dispatch-after-cypress-noop]"
    let tmp = (^mktemp -d | str trim)
    mkdir ($tmp | path join "meta")
    {flow_id: "code-flow"} | save ($tmp | path join "meta/cell.json")
    let report = (dispatch-validators $tmp "after-cypress" "passed")
    ^rm -rf $tmp
    [
        (assert-eq $report.validators [] "after-cypress: validators always empty")
        (assert-null $report.override_outcome "after-cypress: override always null")
    ]
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

# dispatch-validators: malformed cell.json degrades gracefully to noop report.
def test-dispatch-malformed-cell-json [] {
    test-log "\n[test-dispatch-malformed-cell-json]"
    let tmp = (^mktemp -d | str trim)
    mkdir ($tmp | path join "meta")
    "{ not valid json" | save ($tmp | path join "meta/cell.json")
    let report = (dispatch-validators $tmp "after-down" "passed")
    ^rm -rf $tmp
    [
        (assert-eq $report.validators [] "malformed cell.json: validators is empty")
        (assert-null $report.override_outcome "malformed cell.json: override_outcome is null")
        (assert-null $report.override_exit_code "malformed cell.json: override_exit_code is null")
        (assert-eq $report.notes [] "malformed cell.json: notes is empty")
    ]
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
        (test-dispatch-after-down-code-flow-stub)
        | append (test-dispatch-after-down-unknown-flow)
        | append (test-dispatch-after-down-no-cell-json)
        | append (test-dispatch-after-cypress-noop)
        | append (test-dispatch-unknown-stage-noop)
        | append (test-dispatch-malformed-cell-json)
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
