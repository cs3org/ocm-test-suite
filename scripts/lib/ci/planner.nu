# CI planner: expands enabled matrix cells, pre-computes execution_ids,
# resolves capability producers/consumers, and outputs a machine-readable plan.
#
# Plan JSON shape:
#   { schema_version, suite_id, generated_at,
#     cells: [{cell_id, flow_id, scenario, execution_id,
#               sender_platform, sender_version,
#               receiver_platform, receiver_version,
#               is_two_party, capabilities_produced, depends_on}] }

use ../matrix/cells.nu [expand-matrix-cells]
use ../run/execution-id.nu [new-execution-id]
use ../suite/index.nu [new-suite-id]
use ../run/metadata.nu [utc-now]

# Build the canonical capability_id for a login-type capability.
# Format: "<capability_flow>__<platform>-<version>"
export def compute-capability-id [
    capability_flow: string,
    platform: string,
    version: string,
] {
    $"($capability_flow)__($platform)-($version)"
}

# Compute the list of capability_ids produced by a planned cell.
# A cell produces a capability when its flow_id matches a rule's
# capability_flow. One-party login cells produce one capability
# for their sender platform+version.
export def compute-cell-capabilities-produced [
    cell: record,
    prereqs: record,
] {
    let rules = ($prereqs.capability_rules? | default [])
    $rules | each {|rule|
        if $cell.flow_id == $rule.capability_flow {
            [
                (compute-capability-id $rule.capability_flow
                    $cell.sender_platform $cell.sender_version)
            ]
        } else {
            []
        }
    } | flatten
}

# Compute the list of producer cell_ids that a cell depends on.
# For each capability rule, if the cell's flow_id is in required_for_flows,
# we check each required_role and find the producer cell in all_cells that
# provides the matching capability.
export def compute-cell-depends-on [
    cell: record,
    all_cells: list,
    prereqs: record,
] {
    let rules = ($prereqs.capability_rules? | default [])
    $rules | each {|rule|
        if not ($cell.flow_id in $rule.required_for_flows) {
            []
        } else {
            $rule.required_roles | each {|role|
                let need_platform = if $role == "sender" {
                    $cell.sender_platform
                } else if $role == "receiver" {
                    $cell.receiver_platform
                } else { "" }
                let need_version = if $role == "sender" {
                    $cell.sender_version
                } else if $role == "receiver" {
                    $cell.receiver_version
                } else { "" }

                if ($need_platform | is-empty) or ($need_version | is-empty) {
                    []
                } else {
                    let cap_id = (compute-capability-id
                        $rule.capability_flow $need_platform $need_version)
                    # Find a producer cell in all_cells that produces this cap.
                    let producers = ($all_cells | where {|c|
                        (compute-cell-capabilities-produced $c $prereqs)
                        | any {|cap| $cap == $cap_id}
                    })
                    $producers | each {|p| $p.cell_id}
                }
            } | flatten
        }
    } | flatten | uniq
}

# Build a full CI plan from matrix rules and prerequisites config.
# suite_id is generated if not provided.
export def plan-suite [
    rules: record,
    prereqs: record,
    --suite-id: string = "",
] {
    let eff_suite_id = if ($suite_id | is-empty) { new-suite-id } else { $suite_id }
    let all_cells = (expand-matrix-cells $rules)
    let enabled_cells = ($all_cells | where enabled)

    # First pass: compute base cell records with execution_ids.
    let base_cells = ($enabled_cells | each {|c|
        $c | merge {execution_id: (new-execution-id)}
    })

    # Second pass: resolve capabilities_produced and depends_on.
    let planned_cells = ($base_cells | each {|c|
        let caps = (compute-cell-capabilities-produced $c $prereqs)
        let deps = (compute-cell-depends-on $c $base_cells $prereqs)
        $c | merge {
            capabilities_produced: $caps,
            depends_on: $deps,
        }
    })

    {
        schema_version: 1,
        suite_id: $eff_suite_id,
        generated_at: (utc-now),
        cells: $planned_cells,
    }
}
