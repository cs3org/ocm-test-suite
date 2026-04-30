# Shared capability gating helper: single source of truth for per-cell
# capability_status, capability_action, display_visible, display_status,
# requirements, and blockers.
#
# Used by both the CI planner and site display. MUST NOT import from
# ./rules-gen.nu or ../ci/planner.nu to avoid circular imports.

use ../site/blocker-logic.nu [derive-cell-impl-info worst-status-of-blockers]

# Map a raw capability_status to (capability_action, display_visible, display_status).
# Locked mapping (status -> action / display_visible / display_status):
#   supported                  -> run / true / supported
#   test-implementation-pending -> capability-skipped / true / test-pending
#   vendor-unsupported         -> exclude-placeholder / true / vendor-unsupported
#   vendor-out-of-scope        -> exclude-placeholder / false / out-of-scope
#   placeholder                -> exclude-placeholder / true / placeholder
def status-to-gate [status: string] {
    match $status {
        "supported" => {
            capability_action: "run",
            display_visible: true,
            display_status: "supported",
        },
        "test-implementation-pending" => {
            capability_action: "capability-skipped",
            display_visible: true,
            display_status: "test-pending",
        },
        "vendor-unsupported" => {
            capability_action: "exclude-placeholder",
            display_visible: true,
            display_status: "vendor-unsupported",
        },
        "vendor-out-of-scope" => {
            capability_action: "exclude-placeholder",
            display_visible: false,
            display_status: "out-of-scope",
        },
        "placeholder" => {
            capability_action: "exclude-placeholder",
            display_visible: true,
            display_status: "placeholder",
        },
        _ => {
            error make {msg: $"gate-one-cell: unknown capability_status '($status)'; expected one of: supported, test-implementation-pending, vendor-unsupported, vendor-out-of-scope, placeholder"}
        },
    }
}

# Compute gate fields for one cell against the adapter capability map and
# flow capability requirements.
# Returns:
#   { capability_status, capability_action, display_visible, display_status,
#     requirements, blockers }
#
# Cell-level capability_status is the worst across both roles. If the cell has
# enabled: false and the raw status would be "supported", effective status
# becomes "placeholder".
export def gate-one-cell [
    cell: record,
    adapters: record,
    flow_caps: record,
] {
    let valid_statuses = ["supported" "test-implementation-pending" "vendor-unsupported" "vendor-out-of-scope" "placeholder"]
    let info = (derive-cell-impl-info $cell $adapters $flow_caps)
    for b in $info.blockers {
        let s = ($b.status? | default null)
        if $s != null and not ($s in $valid_statuses) {
            error make {msg: $"gate-one-cell: unknown capability_status '($s)'; expected one of: supported, test-implementation-pending, vendor-unsupported, vendor-out-of-scope, placeholder"}
        }
    }
    let raw_status = (worst-status-of-blockers $info.blockers)
    let enabled = ($cell.enabled? | default true)
    let capability_status = if ((not $enabled) and ($raw_status == "supported")) {
        "placeholder"
    } else {
        $raw_status
    }
    let gate = (status-to-gate $capability_status)
    {
        capability_status: $capability_status,
        capability_action: $gate.capability_action,
        display_visible: $gate.display_visible,
        display_status: $gate.display_status,
        requirements: $info.requirements,
        blockers: $info.blockers,
    }
}

# Gate a list of cells by capability, merging gate fields into each cell record.
# Returns the same cells with added fields:
#   capability_status, capability_action, display_visible, display_status,
#   requirements, blockers
export def gate-cells-by-capabilities [
    cells: list,
    adapters: record,
    flow_caps: record,
] {
    $cells | each {|c|
        let g = (gate-one-cell $c $adapters $flow_caps)
        $c | merge $g
    }
}

# Filter gated cells to only those with capability_action == "run".
export def runnable-cells [gated_cells: list] {
    $gated_cells | where capability_action == "run"
}

# Filter gated cells to those with capability_action == "capability-skipped".
export def capability-skipped-cells [gated_cells: list] {
    $gated_cells | where capability_action == "capability-skipped"
}
