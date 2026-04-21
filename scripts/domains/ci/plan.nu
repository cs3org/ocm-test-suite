# Compute and print the CI execution plan as JSON.
# The plan expands all enabled matrix cells, pre-assigns execution_ids, and
# resolves prerequisite dependencies from config/ci/prerequisites.nuon.

use ../../lib/ci/planner.nu [plan-suite]
use ../../lib/domain/core/ocmts-root.nu [get-ocmts-root]

def main [
    --suite-id: string = "",   # Override generated suite_id
    --output: string = "",     # Write plan to this JSON file instead of stdout
    --cell-ids,                # Output only comma-separated cell_ids (for scripting)
] {
    let root = get-ocmts-root
    let rules = open ($root | path join "config/matrix-rules.nuon")
    let prereqs = open ($root | path join "config/ci/prerequisites.nuon")
    let plan = if ($suite_id | is-empty) {
        plan-suite $rules $prereqs
    } else {
        plan-suite $rules $prereqs --suite-id $suite_id
    }
    if $cell_ids {
        $plan.cells | each {|c| $c.cell_id} | str join ","
    } else if ($output | is-empty) {
        $plan | to json --indent 2
    } else {
        $plan | to json --indent 2 | save --force $output
        print $"CI plan written to ($output)"
    }
}
