# Matrix cell runnable drift check.
# Expands matrix cells, gates by adapter/flow capabilities (same path as CI
# planner), and reports enabled cells whose capability_action diverges from
# run. Returns a pure result record for CLI wrappers.

use ../rules-gen.nu [load-matrix-rules]
use ../../site/flow-caps.nu [load-flow-caps]
use ../cells.nu [expand-matrix-cells]
use ../gated-cells.nu [gate-cells-by-capabilities]

const ALLOWED_ACTIONS = ["run" "capability-skipped" "exclude-placeholder"]

def cell-summary [cell: record] {
    {
        cell_id: $cell.cell_id,
        flow_id: $cell.flow_id,
        capability_action: $cell.capability_action,
        capability_status: $cell.capability_status,
    }
}

export def summarize-gated-cells [gated_cells: list] {
    let enabled = ($gated_cells | where {|c| $c.enabled? | default false})
    let divergent = ($enabled
        | where {|c| $c.capability_action != "run"}
        | each {|c| cell-summary $c})
    let cap_skipped = ($enabled
        | where capability_action == "capability-skipped"
        | each {|c| cell-summary $c})
    let excluded = ($enabled
        | where capability_action == "exclude-placeholder"
        | each {|c| cell-summary $c})
    let bad_unknown_action = ($gated_cells
        | where {|c| not ($c.capability_action in $ALLOWED_ACTIONS)})
    let bad_disabled_run = ($gated_cells
        | where {|c| (not ($c.enabled? | default false)) and $c.capability_action == "run"})
    let ok = (($bad_unknown_action | is-empty) and ($bad_disabled_run | is-empty))
    {
        ok: $ok,
        divergent: $divergent,
        cap_skipped: $cap_skipped,
        excluded: $excluded,
    }
}

# Load adapters the same way as scripts/domains/ci/plan.nu and the CI planner.
export def check-cells-runnable [root: string] {
    let rules = (load-matrix-rules $root)
    let flow_caps = (load-flow-caps ($root | path join "config/matrix/flows"))
    let adapters = (open ($root | path join "config/adapters/capabilities.v1.nuon") | get adapters)
    let all_cells = (expand-matrix-cells $rules)
    let gated = (gate-cells-by-capabilities $all_cells $adapters $flow_caps)
    summarize-gated-cells $gated
}
