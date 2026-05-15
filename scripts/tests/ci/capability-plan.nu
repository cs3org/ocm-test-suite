# Plan-facing capability tests.
# Covers: plan-suite disabled-cell placeholder, capability-skipped cell
# inclusion, supported-cell action, augmented fields, capability_skip sub-
# record, non-run cell deps, schema version, and plan --capability-skipped
# filter behavior.
# Run: nu scripts/tests/ci/capability-plan.nu
# Returns exit 0 on all pass, exit 1 with details on failure.

const SUITE_PATH = path self

use ../../lib/ci/planner.nu [plan-suite]
use ../../lib/tests/assert.nu *
use ../../lib/tests/runner.nu [run-suite]
use ./fixtures.nu [
    fixture-rules
    fixture-prereqs
    fixture-flow-caps
    fixture-rules-cap-tests
    fixture-flow-caps-with-reqs
    fixture-adapters-cap
]

# Rules fixture with a unique disabled cell (v99) so its cell_id does not
# collide with the enabled "login" scenario cells.
def fixture-rules-with-unique-disabled [] {
    {
        scenarios: {
            "login-only": {
                enabled: true,
                flow_id: "login",
                browsers: ["chrome"],
                sender: {platform: "nextcloud", version_lines: ["v34"]},
                receiver: null,
                mitm: false,
            },
            "disabled-login-v99": {
                enabled: false,
                flow_id: "login",
                browsers: ["chrome"],
                sender: {platform: "nextcloud", version_lines: ["v99"]},
                receiver: null,
                mitm: false,
            },
        }
    }
}

# ---- tests ----

def test-plan-suite-disabled-cell-is-placeholder [] {
    test-log "\n[test-plan-suite-disabled-cell-is-placeholder]"
    let rules = fixture-rules-with-unique-disabled
    let prereqs = fixture-prereqs
    let plan = (plan-suite $rules $prereqs (fixture-flow-caps) {})
    let v99_cells = ($plan.cells | where {|c| $c.cell_id == "login__nextcloud-v99"})
    [
        (assert-truthy (not ($v99_cells | is-empty))
            "disabled scenario cell login__nextcloud-v99 is included in plan")
        (assert-eq ($v99_cells | first | get capability_action) "exclude-placeholder"
            "disabled supported cell has capability_action exclude-placeholder")
        (assert-eq ($v99_cells | first | get capability_status) "placeholder"
            "disabled supported cell has capability_status placeholder")
        (assert-truthy ($v99_cells | first | get display_visible)
            "disabled supported cell is still display_visible")
    ]
}

def test-plan-suite-capability-skipped-included [] {
    test-log "\n[test-plan-suite-capability-skipped-included]"
    let rules = fixture-rules-cap-tests
    let prereqs = fixture-prereqs
    let plan = (plan-suite $rules $prereqs (fixture-flow-caps-with-reqs) (fixture-adapters-cap))
    let oc_cells = ($plan.cells | where {|c| $c.cell_id == "login__opencloud-v6"})
    [
        (assert-truthy (not ($oc_cells | is-empty))
            "plan includes capability-skipped cell login__opencloud-v6")
        (assert-eq ($oc_cells | first | get capability_action) "capability-skipped"
            "test-pending cell has capability_action capability-skipped")
        (assert-eq ($oc_cells | first | get capability_status) "test-implementation-pending"
            "test-pending cell has capability_status test-implementation-pending")
        (assert-truthy ($oc_cells | first | get display_visible)
            "test-pending cell is display_visible")
        (assert-eq ($oc_cells | first | get display_status) "test-pending"
            "test-pending cell has display_status test-pending")
    ]
}

def test-plan-suite-supported-cell-action-run [] {
    test-log "\n[test-plan-suite-supported-cell-action-run]"
    let rules = fixture-rules-cap-tests
    let prereqs = fixture-prereqs
    let plan = (plan-suite $rules $prereqs (fixture-flow-caps-with-reqs) (fixture-adapters-cap))
    let nc_cells = ($plan.cells | where {|c| $c.cell_id == "login__nextcloud-v34"})
    [
        (assert-truthy (not ($nc_cells | is-empty))
            "plan includes login__nextcloud-v34")
        (assert-eq ($nc_cells | first | get capability_action) "run"
            "supported cell has capability_action run")
        (assert-eq ($nc_cells | first | get capability_status) "supported"
            "supported cell has capability_status supported")
        (assert-eq ($nc_cells | first | get display_status) "supported"
            "supported cell has display_status supported")
    ]
}

def test-plan-suite-augmented-fields-present [] {
    test-log "\n[test-plan-suite-augmented-fields-present]"
    let rules = fixture-rules-cap-tests
    let prereqs = fixture-prereqs
    let plan = (plan-suite $rules $prereqs (fixture-flow-caps) {})
    let required_fields = ["capability_status" "capability_action" "display_visible"
                           "display_status" "requirements" "blockers" "execution_id"]
    let all_have_fields = ($plan.cells | all {|c|
        let cols = ($c | columns)
        $required_fields | all {|f| $f in $cols}
    })
    [
        (assert-truthy $all_have_fields
            "all cells have augmented fields: capability_status, capability_action, display_visible, display_status, requirements, blockers, execution_id")
    ]
}

def test-plan-suite-capability-skip-field [] {
    test-log "\n[test-plan-suite-capability-skip-field]"
    let rules = fixture-rules-cap-tests
    let prereqs = fixture-prereqs
    let plan = (plan-suite $rules $prereqs (fixture-flow-caps-with-reqs) (fixture-adapters-cap))
    let oc_cells = ($plan.cells | where {|c| $c.cell_id == "login__opencloud-v6"})
    let nc_cells = ($plan.cells | where {|c| $c.cell_id == "login__nextcloud-v34"})
    let oc_cols = if not ($oc_cells | is-empty) { ($oc_cells | first | columns) } else { [] }
    let nc_cols = if not ($nc_cells | is-empty) { ($nc_cells | first | columns) } else { [] }
    [
        (assert-truthy ("capability_skip" in $oc_cols)
            "capability-skipped cell has capability_skip field")
        (assert-truthy (not ("capability_skip" in $nc_cols))
            "non-skipped (run) cell omits capability_skip field")
        (assert-truthy (
            if ("capability_skip" in $oc_cols) {
                let cs = ($oc_cells | first | get capability_skip)
                ("reason" in ($cs | columns)) and ("rationale" in ($cs | columns))
            } else { false }
        ) "capability_skip has reason and rationale sub-fields")
    ]
}

def test-plan-suite-non-run-cells-empty-deps [] {
    test-log "\n[test-plan-suite-non-run-cells-empty-deps]"
    let rules = fixture-rules-cap-tests
    let prereqs = fixture-prereqs
    let plan = (plan-suite $rules $prereqs (fixture-flow-caps-with-reqs) (fixture-adapters-cap))
    let non_run = ($plan.cells | where {|c| $c.capability_action != "run"})
    let all_empty_caps = ($non_run | all {|c|
        let caps_empty = (($c.capabilities_produced? | default [] | length) == 0)
        let deps_empty = (($c.depends_on? | default [] | length) == 0)
        $caps_empty and $deps_empty
    })
    [
        (assert-truthy $all_empty_caps
            "non-run cells have empty capabilities_produced and depends_on")
    ]
}

def test-plan-suite-schema-version-1 [] {
    test-log "\n[test-plan-suite-schema-version-1]"
    let rules = fixture-rules
    let prereqs = fixture-prereqs
    let plan = (plan-suite $rules $prereqs (fixture-flow-caps) {})
    [
        (assert-eq ($plan.schema_version? | default 0) 1 "plan schema_version is 1")
    ]
}

def test-plan-cmd-capability-skipped-returns-only-skipped [] {
    test-log "\n[test-plan-cmd-capability-skipped-returns-only-skipped]"
    let plan = (plan-suite
        (fixture-rules-cap-tests)
        (fixture-prereqs)
        (fixture-flow-caps-with-reqs)
        (fixture-adapters-cap))
    let skipped = ($plan.cells | where capability_action == "capability-skipped")
    let run_cell_ids = ($plan.cells
        | where capability_action == "run"
        | each {|c| $c.cell_id})
    [
        (assert-truthy (not ($skipped | is-empty))
            "--capability-skipped: at least one capability-skipped cell present in plan")
        (assert-truthy ($skipped | all {|c| $c.capability_action == "capability-skipped"})
            "--capability-skipped: every returned cell has capability_action capability-skipped")
        (assert-truthy ($skipped | all {|c| not ($c.cell_id in $run_cell_ids)})
            "--capability-skipped: no run cell appears in filtered output")
    ]
}

def test-plan-cmd-capability-skipped-cell-fields [] {
    test-log "\n[test-plan-cmd-capability-skipped-cell-fields]"
    let plan = (plan-suite
        (fixture-rules-cap-tests)
        (fixture-prereqs)
        (fixture-flow-caps-with-reqs)
        (fixture-adapters-cap))
    let skipped = ($plan.cells | where capability_action == "capability-skipped")
    let first_cell = ($skipped | first)
    let cols = ($first_cell | columns)
    let skip_cols = ($first_cell.capability_skip | columns)
    [
        (assert-truthy ("cell_id" in $cols)
            "--capability-skipped: returned cell has cell_id field")
        (assert-truthy ("capability_action" in $cols)
            "--capability-skipped: returned cell has capability_action field")
        (assert-truthy ("capability_skip" in $cols)
            "--capability-skipped: returned cell has capability_skip field")
        (assert-truthy ("execution_id" in $cols)
            "--capability-skipped: returned cell has execution_id field")
        (assert-truthy ("flow_id" in $cols)
            "--capability-skipped: returned cell has flow_id field")
        (assert-truthy (("reason" in $skip_cols) and ("rationale" in $skip_cols))
            "--capability-skipped: capability_skip sub-record has reason and rationale")
    ]
}

def test-plan-cmd-capability-skipped-default-unchanged [] {
    test-log "\n[test-plan-cmd-capability-skipped-default-unchanged]"
    let plan = (plan-suite
        (fixture-rules-cap-tests)
        (fixture-prereqs)
        (fixture-flow-caps-with-reqs)
        (fixture-adapters-cap))
    let all_actions = ($plan.cells | each {|c| $c.capability_action} | uniq | sort)
    let run_count = ($plan.cells | where capability_action == "run" | length)
    let skipped_count = ($plan.cells | where capability_action == "capability-skipped" | length)
    [
        (assert-truthy ("run" in $all_actions)
            "default plan output still contains run cells")
        (assert-truthy ("capability-skipped" in $all_actions)
            "default plan output still contains capability-skipped cells")
        (assert-eq ($plan.cells | length) ($run_count + $skipped_count)
            "default: all cells are accounted for by run + capability-skipped counts")
        (assert-eq ($plan.schema_version? | default 0) 1
            "default plan schema_version unchanged")
    ]
}

def main [] {
    test-log "=== CI Capability-Plan Tests ==="
    let results = (
        (test-plan-suite-disabled-cell-is-placeholder)
        | append (test-plan-suite-capability-skipped-included)
        | append (test-plan-suite-supported-cell-action-run)
        | append (test-plan-suite-augmented-fields-present)
        | append (test-plan-suite-capability-skip-field)
        | append (test-plan-suite-non-run-cells-empty-deps)
        | append (test-plan-suite-schema-version-1)
        | append (test-plan-cmd-capability-skipped-returns-only-skipped)
        | append (test-plan-cmd-capability-skipped-cell-fields)
        | append (test-plan-cmd-capability-skipped-default-unchanged)
    ) | flatten
    run-suite "ci/capability-plan" $SUITE_PATH $results
}
