# Compute and print the CI execution plan as JSON.
# Emits a CI plan record (suite_id, cells) that expands every
# matrix cell, gates by capability, pre-assigns execution_ids, and resolves
# prerequisite dependencies from config/ci/prerequisites.nuon.

use ../../lib/ci/planner.nu [plan-suite]
use ../../lib/domain/core/ocmts-root.nu [get-ocmts-root]
use ../../lib/matrix/rules-gen.nu [load-matrix-rules]
use ../../lib/site/flow-caps.nu [load-flow-caps]

def main [
    --suite-id: string = "",              # Override generated suite_id
    --output: string = "",                # Write plan to this JSON file instead of stdout
    --cell-ids,                           # Output only comma-separated cell_ids (for scripting)
    --capability-skipped,                 # Output capability-skipped cell records as JSON array to stdout
    --capability-skipped-json: string = "", # Write capability-skipped cell records to this JSON file
] {
    let root = get-ocmts-root
    let rules = (load-matrix-rules $root)
    let prereqs = open ($root | path join "config/ci/prerequisites.nuon")
    let flow_caps = (load-flow-caps ($root | path join "config/matrix/flows"))
    let adapters = (open ($root | path join "config/adapters/capabilities.v1.nuon") | get adapters)
    let plan = if ($suite_id | is-empty) {
        plan-suite $rules $prereqs $flow_caps $adapters
    } else {
        plan-suite $rules $prereqs $flow_caps $adapters --suite-id $suite_id
    }
    if $cell_ids {
        $plan.cells | each {|c| $c.cell_id} | str join ","
    } else if $capability_skipped {
        let skipped = ($plan.cells | where capability_action == "capability-skipped")
        $skipped | to json --indent 2
    } else if (not ($capability_skipped_json | is-empty)) {
        let skipped = ($plan.cells | where capability_action == "capability-skipped")
        $skipped | to json --indent 2 | save --force $capability_skipped_json
        print $"Capability-skipped cells written to ($capability_skipped_json)"
    } else if ($output | is-empty) {
        $plan | to json --indent 2
    } else {
        $plan | to json --indent 2 | save --force $output
        print $"CI plan written to ($output)"
    }
}
