# CI planner and blocker core tests.
# Covers: compute-capability-id, compute-cell-capabilities-produced,
# compute-cell-depends-on, plan-suite shape, blocked/transitive-blocked eval,
# status-precedence delegation, flow-order sorting.
# Workflow-generation tests live in scripts/tests/ci/workflow-gen.nu.
# Aggregate tests live in scripts/tests/ci/aggregate.nu.
# Suite-index tests live in scripts/tests/ci/suite-index.nu.
# Site-ingest tests live in scripts/tests/ci/site-ingest.nu.
# Capability-plan tests live in scripts/tests/ci/capability-plan.nu.
# Capability-artifact tests live in scripts/tests/ci/capability-artifacts.nu.
# Run: nu scripts/tests/ci/planner.nu
# Returns exit 0 on all pass, exit 1 with details on failure.

const SUITE_PATH = path self

use ../../lib/ci/planner.nu [
    plan-suite
    compute-capability-id
    compute-cell-capabilities-produced
    compute-cell-depends-on
]
use ../../lib/ci/blocker.nu [eval-blocked-cells]
use ../../lib/ci/aggregate.nu [aggregate-status]
use ../../lib/ci/flow-order.nu [sort-cells-by-flow-order]
use ../../lib/run/status.nu [run-status-precedence]
use ../../lib/suite/index.nu [compute-suite-status]
use ../../lib/tests/assert.nu *
use ../../lib/tests/fixtures.nu [make-cell]
use ../../lib/tests/runner.nu [run-suite]
use ./fixtures.nu [fixture-rules fixture-prereqs fixture-flow-caps]

# ---- tests ----

def test-capability-id [] {
    test-log "\n[test-capability-id]"
    let results = [
        (assert-eq
            (compute-capability-id "login" "nextcloud" "v34")
            "login__nextcloud-v34"
            "login nextcloud-v34 capability id")
        (assert-eq
            (compute-capability-id "login" "ocmgo" "v1")
            "login__ocmgo-v1"
            "login ocmgo-v1 capability id")
        (assert-eq
            (compute-capability-id "login" "ocis" "v8")
            "login__ocis-v8"
            "login ocis-v8 capability id")
    ]
    $results
}

def test-cell-capabilities-produced [] {
    test-log "\n[test-cell-capabilities-produced]"
    let prereqs = fixture-prereqs
    let login_cell = {
        cell_id: "login__nextcloud-v34",
        flow_id: "login",
        sender_platform: "nextcloud",
        sender_version: "v34",
        receiver_platform: "",
        receiver_version: "",
        is_two_party: false,
    }
    let share_cell = {
        cell_id: "share-with__nextcloud-v34__nextcloud-v34",
        flow_id: "share-with",
        sender_platform: "nextcloud",
        sender_version: "v34",
        receiver_platform: "nextcloud",
        receiver_version: "v34",
        is_two_party: true,
    }
    let login_caps = (compute-cell-capabilities-produced $login_cell $prereqs)
    let share_caps = (compute-cell-capabilities-produced $share_cell $prereqs)
    [
        (assert-list-contains $login_caps "login__nextcloud-v34" "login cell produces login capability")
        (assert-eq ($share_caps | length) 0 "share-with cell produces no capabilities")
    ]
}

def test-cell-depends-on [] {
    test-log "\n[test-cell-depends-on]"
    let prereqs = fixture-prereqs
    # login cells from the matrix
    let login_v33_cell = {
        cell_id: "login__nextcloud-v33",
        flow_id: "login",
        sender_platform: "nextcloud",
        sender_version: "v33",
        receiver_platform: "",
        receiver_version: "",
        is_two_party: false,
    }
    let login_v34_cell = {
        cell_id: "login__nextcloud-v34",
        flow_id: "login",
        sender_platform: "nextcloud",
        sender_version: "v34",
        receiver_platform: "",
        receiver_version: "",
        is_two_party: false,
    }
    let share_cell = {
        cell_id: "share-with__nextcloud-v34__nextcloud-v34",
        flow_id: "share-with",
        sender_platform: "nextcloud",
        sender_version: "v34",
        receiver_platform: "nextcloud",
        receiver_version: "v34",
        is_two_party: true,
    }
    let all_cells = [$login_v33_cell $login_v34_cell $share_cell]
    let share_deps = (compute-cell-depends-on $share_cell $all_cells $prereqs)
    let login_deps = (compute-cell-depends-on $login_v34_cell $all_cells $prereqs)
    [
        (assert-list-contains $share_deps "login__nextcloud-v34"
            "share-with v34-v34 depends on login__nextcloud-v34")
        (assert-list-not-contains $share_deps "login__nextcloud-v33"
            "share-with v34-v34 does NOT depend on login__nextcloud-v33")
        (assert-eq ($login_deps | length) 0 "login cell has no dependencies")
    ]
}

def test-plan-suite [] {
    test-log "\n[test-plan-suite]"
    let rules = fixture-rules
    let prereqs = fixture-prereqs
    let plan = (plan-suite $rules $prereqs (fixture-flow-caps) {})
    let cell_ids = ($plan.cells | each {|c| $c.cell_id})
    [
        (assert-truthy (($plan.suite_id | str length) > 0) "plan has suite_id")
        (assert-eq ($plan.schema_version? | default 0) 1 "schema_version is 1")
        (assert-list-contains $cell_ids "login__nextcloud-v34"
            "plan includes login__nextcloud-v34")
        (assert-truthy (
            $plan.cells
            | where {|c| $c.cell_id == "login__nextcloud-v34"}
            | each {|c| ($c.execution_id | str length) > 0}
            | any {|v| $v}
        ) "each cell has execution_id")
        (assert-truthy (
            $plan.cells
            | where {|c| $c.cell_id == "login__nextcloud-v34"}
            | each {|c| ($c | columns | any {|f| $f == "capability_action"})}
            | any {|v| $v}
        ) "cells have capability_action field")
    ]
}

def test-plan-suite-nextcloud-v34-login-is-producer [] {
    test-log "\n[test-plan-suite-nextcloud-v34-login-is-producer]"
    let rules = fixture-rules
    let prereqs = fixture-prereqs
    let plan = (plan-suite $rules $prereqs (fixture-flow-caps) {})
    let login_v34 = ($plan.cells | where {|c| $c.cell_id == "login__nextcloud-v34"} | first)
    [
        (assert-list-contains $login_v34.capabilities_produced "login__nextcloud-v34"
            "login__nextcloud-v34 cell produces login capability for nextcloud-v34")
    ]
}

def test-blocked-eval [] {
    test-log "\n[test-blocked-eval]"
    let prereqs = fixture-prereqs
    let login_v34_cell = {
        cell_id: "login__nextcloud-v34",
        flow_id: "login",
        matrix_key: "login__nextcloud",
        sender_platform: "nextcloud",
        sender_version: "v34",
        receiver_platform: "",
        receiver_version: "",
        is_two_party: false,
        execution_id: "20260101t000000-aaaaaaaa",
        capabilities_produced: ["login__nextcloud-v34"],
        depends_on: [],
    }
    let share_cell = {
        cell_id: "share-with__nextcloud-v34__nextcloud-v34",
        flow_id: "share-with",
        matrix_key: "share-with__nextcloud__nextcloud",
        sender_platform: "nextcloud",
        sender_version: "v34",
        receiver_platform: "nextcloud",
        receiver_version: "v34",
        is_two_party: true,
        execution_id: "20260101t000001-bbbbbbbb",
        capabilities_produced: [],
        depends_on: ["login__nextcloud-v34"],
    }
    let planned_cells = [$login_v34_cell $share_cell]
    # Simulate: login__nextcloud-v34 failed
    let failed_cell_ids = ["login__nextcloud-v34"]
    let result = (eval-blocked-cells $planned_cells $failed_cell_ids)
    let share_entry = ($result | where {|r| $r.cell_id == "share-with__nextcloud-v34__nextcloud-v34"} | first)
    [
        (assert-truthy $share_entry.blocked
            "share-with cell is blocked when login__nextcloud-v34 fails")
        (assert-truthy (($share_entry.failure_reason | str contains "login__nextcloud-v34"))
            "blocked failure_reason names the failed prerequisite")
        (assert-eq (
            $result
            | where {|r| $r.cell_id == "login__nextcloud-v34"}
            | first
            | get blocked
        ) false "login cell itself is not blocked")
    ]
}

def test-blocked-result-status [] {
    test-log "\n[test-blocked-result-status]"
    # The blocked record shape: status == "blocked", failure_reason non-empty
    let planned_cells = [
        {
            cell_id: "share-with__nextcloud-v34__nextcloud-v34",
            flow_id: "share-with",
            matrix_key: "share-with__nextcloud__nextcloud",
            sender_platform: "nextcloud",
            sender_version: "v34",
            receiver_platform: "nextcloud",
            receiver_version: "v34",
            is_two_party: true,
            execution_id: "20260101t000001-bbbbbbbb",
            capabilities_produced: [],
            depends_on: ["login__nextcloud-v34"],
        }
    ]
    let failed_ids = ["login__nextcloud-v34"]
    let result = (eval-blocked-cells $planned_cells $failed_ids)
    let entry = ($result | first)
    [
        (assert-eq $entry.status "blocked" "blocked entry has status=blocked")
        (assert-truthy (not ($entry.failure_reason | is-empty))
            "blocked entry has non-empty failure_reason")
    ]
}

def test-transitive-blocked [] {
    test-log "\n[test-transitive-blocked]"
    # Three-level chain: A (fails) -> B (blocked) -> C (should be transitively blocked)
    let cell_a = (make-cell {cell_id: "a"})
    let cell_b = (make-cell {
        cell_id: "b",
        flow_id: "share-with",
        matrix_key: "share-with__nextcloud__nextcloud",
        receiver_platform: "nextcloud",
        receiver_version: "v34",
        is_two_party: true,
        depends_on: ["a"],
    })
    let cell_c = (make-cell {
        cell_id: "c",
        flow_id: "share-with",
        matrix_key: "share-with__nextcloud__nextcloud",
        receiver_platform: "nextcloud",
        receiver_version: "v34",
        is_two_party: true,
        depends_on: ["b"],
    })

    # Step 1: A fails -> B is blocked
    let failed_ids = ["a"]
    let b_eval = (eval-blocked-cells [$cell_b] $failed_ids)
    let b_entry = ($b_eval | first)

    # Step 2: simulate suite loop: unavailable = failed + blocked
    let blocked_ids = if $b_entry.blocked { ["b"] } else { [] }
    let unavailable = ($failed_ids | append $blocked_ids)

    # Step 3: C depends on B (blocked) -> C should be blocked transitively
    let c_eval = (eval-blocked-cells [$cell_c] $unavailable)
    let c_entry = ($c_eval | first)

    [
        (assert-truthy $b_entry.blocked "cell B is blocked when A fails")
        (assert-truthy $c_entry.blocked
            "cell C is transitively blocked when B is blocked (unavailable set includes blocked)")
        (assert-truthy (not ($c_entry.failure_reason | is-empty))
            "transitively blocked cell C has non-empty failure_reason")
    ]
}

# Thin delegation check: wrappers must agree with run-status-precedence.
# Canonical precedence coverage lives in scripts/tests/run/status.nu.
def test-precedence-wrappers-delegate [] {
    test-log "\n[test-precedence-wrappers-delegate]"
    let input = ["passed" "infra-failed" "blocked"]
    [
        (assert-eq (compute-suite-status $input) (run-status-precedence $input)
            "compute-suite-status delegates to run-status-precedence")
        (assert-eq (aggregate-status $input) (run-status-precedence $input)
            "aggregate-status delegates to run-status-precedence")
    ]
}

def test-sort-cells-by-flow-order [] {
    test-log "\n[test-sort-cells-by-flow-order]"
    let cells = [
        {cell_id: "contact-token__nextcloud-v34__nextcloud-v34", flow_id: "contact-token"}
        {cell_id: "login__nextcloud-v34", flow_id: "login"}
        {cell_id: "share-with__nextcloud-v34__nextcloud-v34", flow_id: "share-with"}
    ]
    let job_order = ["login", "share-with", "contact-token", "contact-wayf"]
    let sorted = (sort-cells-by-flow-order $cells $job_order)
    let ids = ($sorted | each {|c| $c.cell_id})
    [
        (assert-eq ($ids | first) "login__nextcloud-v34"
            "login cell sorts first")
        (assert-eq ($ids | get 1) "share-with__nextcloud-v34__nextcloud-v34"
            "share-with cell sorts second")
        (assert-eq ($ids | last) "contact-token__nextcloud-v34__nextcloud-v34"
            "contact-token cell sorts last")
    ]
}

# Verify that sort-then-max preserves flow order rather than plan order.
# This mirrors what local `test suite --max N` does: sort first, then take
# the first N, so that --max 1 always picks the first flow-ordered cell.
def test-suite-sort-then-max-respects-flow-order [] {
    test-log "\n[test-suite-sort-then-max-respects-flow-order]"
    # Reverse order relative to job_order to simulate unordered planner output.
    let cells = [
        {cell_id: "share-with__nextcloud-v34__nextcloud-v34", flow_id: "share-with"}
        {cell_id: "contact-token__nextcloud-v34__nextcloud-v34", flow_id: "contact-token"}
        {cell_id: "login__nextcloud-v34", flow_id: "login"}
    ]
    let job_order = ["login", "share-with", "contact-token", "contact-wayf"]
    let sorted = (sort-cells-by-flow-order $cells $job_order)

    let max1 = ($sorted | first 1)
    let max2 = ($sorted | first 2)

    [
        (assert-eq ($max1 | first | get cell_id) "login__nextcloud-v34"
            "--max 1 picks login (first in flow order)")
        (assert-eq ($max2 | get 0 | get cell_id) "login__nextcloud-v34"
            "--max 2 first cell is login")
        (assert-eq ($max2 | get 1 | get cell_id) "share-with__nextcloud-v34__nextcloud-v34"
            "--max 2 second cell is share-with")
    ]
}

# compute-cell-depends-on must error on an unrecognised required_role value.
def test-compute-cell-depends-on-rejects-unknown-role [] {
    test-log "\n[test-compute-cell-depends-on-rejects-unknown-role]"
    let cell = {
        cell_id: "share-with__nextcloud-v34__nextcloud-v34",
        flow_id: "share-with",
        matrix_key: "share-with__nextcloud__nextcloud",
        sender_platform: "nextcloud",
        sender_version: "v34",
        receiver_platform: "nextcloud",
        receiver_version: "v34",
        is_two_party: true,
        enabled: true,
        browser: "chrome",
    }
    let bad_prereqs = {
        capability_rules: [{
            capability_flow: "login",
            required_for_flows: ["share-with"],
            required_roles: ["bogus"],
        }]
    }
    let err = (try {
        compute-cell-depends-on $cell [] $bad_prereqs
        ""
    } catch {|e| $e.msg})
    [
        (assert-string-contains $err "compute-cell-depends-on"
            "error names the function")
        (assert-string-contains $err "bogus"
            "error names the unknown role value")
        (assert-string-contains $err "unknown required_role"
            "error describes the problem")
    ]
}

def main [] {
    test-log "=== CI Planner Tests ==="
    let results = (
        (test-capability-id)
        | append (test-cell-capabilities-produced)
        | append (test-cell-depends-on)
        | append (test-plan-suite)
        | append (test-plan-suite-nextcloud-v34-login-is-producer)
        | append (test-blocked-eval)
        | append (test-blocked-result-status)
        | append (test-transitive-blocked)
        | append (test-precedence-wrappers-delegate)
        | append (test-sort-cells-by-flow-order)
        | append (test-suite-sort-then-max-respects-flow-order)
        | append (test-compute-cell-depends-on-rejects-unknown-role)
    ) | flatten
    run-suite "ci/planner" $SUITE_PATH $results
}
