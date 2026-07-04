# Capability artifact emission and flow-asset exclusion behavior
# for capability-skipped cells.
# Covers: flow asset exclusion, ci-matrix yml exclusion, cell artifact files.
# Run: nu scripts/tests/ci/capability-artifacts.nu
# Returns exit 0 on all pass, exit 1 with details on failure.

const SUITE_PATH = path self

use ../../lib/ci/planner.nu [plan-suite]
use ../../lib/ci/workflow-gen.nu [build-flow-assets build-ci-matrix-yml]
use ../../lib/tests/assert.nu *
use ../../lib/tests/runner.nu [run-suite]
use ./fixtures.nu [
    fixture-prereqs
    fixture-rules-cap-tests
    fixture-flow-caps-with-reqs
    fixture-adapters-cap
    fixture-rules-only-cap-skipped
]

# ---- tests ----

def test-build-flow-assets-excludes-cap-skipped [] {
    test-log "\n[test-build-flow-assets-excludes-cap-skipped]"
    let rules = fixture-rules-cap-tests
    let prereqs = fixture-prereqs
    let plan = (plan-suite $rules $prereqs (fixture-flow-caps-with-reqs) (fixture-adapters-cap))
    let flow_assets = (build-flow-assets $plan)

    # The plan has login__nextcloud-v34 (run) and login__opencloud-v6 (capability-skipped).
    # flow_assets should only contain the runnable cell.
    let all_cell_ids = ($flow_assets | each {|a|
        $a.content | from json | each {|c| $c.cell_id}
    } | flatten)
    [
        (assert-truthy (not ($all_cell_ids | is-empty))
            "flow assets: at least one cell present")
        (assert-truthy ("login__nextcloud-v34" in $all_cell_ids)
            "flow assets: runnable cell login__nextcloud-v34 included")
        (assert-truthy (not ("login__opencloud-v6" in $all_cell_ids))
            "flow assets: capability-skipped cell login__opencloud-v6 excluded")
    ]
}

def test-build-flow-assets-omits-cap-skipped-only-flow [] {
    test-log "\n[test-build-flow-assets-omits-cap-skipped-only-flow]"
    let rules = fixture-rules-only-cap-skipped
    let prereqs = fixture-prereqs
    let plan = (plan-suite $rules $prereqs (fixture-flow-caps-with-reqs) (fixture-adapters-cap))
    let flow_assets = (build-flow-assets $plan)
    [
        (assert-truthy ($flow_assets | is-empty)
            "flow assets: no assets for flow with only capability-skipped cells")
    ]
}

def test-build-ci-matrix-yml-excludes-cap-skipped-only-flow [] {
    test-log "\n[test-build-ci-matrix-yml-excludes-cap-skipped-only-flow]"
    let rules = fixture-rules-only-cap-skipped
    let prereqs = fixture-prereqs
    let plan = (plan-suite $rules $prereqs (fixture-flow-caps-with-reqs) (fixture-adapters-cap))
    let yml = (build-ci-matrix-yml $plan)
    # There should be no flow job for "login" since all cells are capability-skipped.
    [
        (assert-truthy (not ($yml | str contains "  login:"))
            "ci-matrix.yml: no login flow job when all cells are capability-skipped")
    ]
}

def test-emit-capability-skipped-cell-artifact [] {
    test-log "\n[test-emit-capability-skipped-cell-artifact]"
    use ../../lib/ci/blocker.nu [emit-capability-skipped-cell-artifact]
    let tmp = (^mktemp -d | str trim)
    let ts = "2026-01-01T00:00:00Z"
    let planned_cell = {
        cell_id: "login__opencloud-v6",
        artifact_name: "cell-login-opencloud-v6",
        flow_id: "login",
        matrix_key: "login__opencloud",
        pair: "opencloud-v6",
        sender_platform: "opencloud",
        sender_version: "v6",
        receiver_platform: "",
        receiver_version: "",
        is_two_party: false,
        browser: "chrome",
        execution_id: "20260101t000000-aabbccdd",
        capability_skip: {
            reason: "test-implementation-pending",
            blocked_capability: "flow.login.sender",
            blocked_role: "sender",
            blocked_adapter_key: "opencloud/v6",
            rationale: "Login sender not yet implemented for opencloud v6",
        },
    }
    let artifacts_base = (try {
        emit-capability-skipped-cell-artifact $tmp $planned_cell
    } catch {|e|
        print $"  FAIL: emit-capability-skipped-cell-artifact threw: ($e.msg)"
        ""
    })

    let cell_json_path = ($artifacts_base | path join "meta/cell.json")
    let run_json_path = ($artifacts_base | path join "meta/run.json")
    let result_json_path = ($artifacts_base | path join "meta/result.v1.json")

    let cell_exists = ($cell_json_path | path exists)
    let run_exists = ($run_json_path | path exists)
    let result_exists = ($result_json_path | path exists)

    let run_data = if $run_exists { open $run_json_path } else { {} }
    let result_data = if $result_exists { open $result_json_path } else { {} }

    ^rm -rf $tmp
    [
        (assert-truthy (not ($artifacts_base | is-empty))
            "emit-capability-skipped-cell-artifact returns a non-empty path")
        (assert-truthy $cell_exists
            "meta/cell.json written")
        (assert-truthy $run_exists
            "meta/run.json written")
        (assert-truthy $result_exists
            "meta/result.v1.json written")
        (assert-eq ($run_data.status? | default "") "capability-skipped"
            "run.json status is capability-skipped")
        (assert-eq ($run_data.matrix_key? | default "") "login__opencloud"
            "run.json has matrix_key from planned cell")
        (assert-eq ($run_data.exit_code? | default (-1)) 0
            "run.json exit_code is 0")
        (assert-eq ($result_data.status? | default "") "capability-skipped"
            "result.v1.json status is capability-skipped")
        (assert-eq ($result_data.matrix_key? | default "") "login__opencloud"
            "result.v1.json has matrix_key from planned cell")
        (assert-eq ($result_data.exit_code? | default (-1)) 0
            "result.v1.json exit_code is 0")
        (assert-truthy ($result_data.capability_skip? != null)
            "result.v1.json preserves capability_skip record")
        (assert-eq ($result_data.failure_reason? | default "unset")
            "Login sender not yet implemented for opencloud v6"
            "result.v1.json failure_reason matches capability_skip.rationale")
    ]
}

def main [] {
    test-log "=== CI Capability Artifacts Tests ==="
    let results = (
        (test-build-flow-assets-excludes-cap-skipped)
        | append (test-build-flow-assets-omits-cap-skipped-only-flow)
        | append (test-build-ci-matrix-yml-excludes-cap-skipped-only-flow)
        | append (test-emit-capability-skipped-cell-artifact)
    ) | flatten
    run-suite "ci/capability-artifacts" $SUITE_PATH $results
}
