# CI planner: expands matrix cells, gates by capabilities, pre-computes
# execution_ids, resolves capability producers/consumers, and outputs a
# machine-readable plan.
#
# Plan JSON shape:
#   { schema_version, suite_id, generated_at,
#     cells: [{cell_id, flow_id, matrix_key, execution_id,
#               sender_platform, sender_version,
#               receiver_platform, receiver_version,
#               is_two_party,
#               capability_status, capability_action, display_visible,
#               display_status, requirements, blockers,
#               capabilities_produced, depends_on,
#               [capability_skip]}] }
#
# All cells (enabled, disabled, capability-skipped) are present.
# Only runnable cells (capability_action == "run") get meaningful
# capabilities_produced and depends_on. Non-run cells get [] for both.
# capability_skip is present only on capability-skipped cells.

use ../matrix/cells.nu [expand-matrix-cells]
use ../matrix/gated-cells.nu [gate-cells-by-capabilities]
use ../matrix/status-rank.nu [pick-worst-blocker]
use ../run/execution-id.nu [new-execution-id]
use ../suite/index.nu [new-suite-id]
use ../time/utc.nu [utc-now]

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
    # Validate required_roles before closure processing so errors propagate directly.
    for rule in $rules {
        for role in $rule.required_roles {
            if $role != "sender" and $role != "receiver" {
                error make {msg: $"compute-cell-depends-on: unknown required_role '($role)' in capability_rules; expected 'sender' or 'receiver'"}
            }
        }
    }
    $rules | each {|rule|
        if not ($cell.flow_id in $rule.required_for_flows) {
            []
        } else {
            $rule.required_roles | each {|role|
                let need_platform = if $role == "sender" {
                    $cell.sender_platform
                } else {
                    $cell.receiver_platform
                }
                let need_version = if $role == "sender" {
                    $cell.sender_version
                } else {
                    $cell.receiver_version
                }

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

# Build a full CI plan from matrix rules, prerequisites config, flow capabilities,
# and adapter capabilities. suite_id is generated if not provided.
#
# All cells (enabled, disabled, capability-skipped) appear in the output.
# Only cells with capability_action == "run" get meaningful capabilities_produced
# and depends_on. capability_skip is present only for capability-skipped cells.
export def plan-suite [
    rules: record,
    prereqs: record,
    flow_caps: record,
    adapters: record,
    --suite-id: string = "",
] {
    let eff_suite_id = if ($suite_id | is-empty) { new-suite-id } else { $suite_id }
    let all_cells = (expand-matrix-cells $rules)

    # Gate all cells for capability information.
    let gated_cells = (gate-cells-by-capabilities $all_cells $adapters $flow_caps)

    # First pass: assign execution_ids to all cells.
    let base_cells = ($gated_cells | each {|c|
        $c | merge {execution_id: (new-execution-id)}
    })

    # Runnable cells are the producer/dependency universe.
    let runnable = ($base_cells | where capability_action == "run")

    # Second pass: resolve capabilities for runnable cells; empty for all others.
    let planned_cells = ($base_cells | each {|c|
        if $c.capability_action == "run" {
            let caps = (compute-cell-capabilities-produced $c $prereqs)
            let deps = (compute-cell-depends-on $c $runnable $prereqs)
            $c | merge {
                capabilities_produced: $caps,
                depends_on: $deps,
            }
        } else {
            $c | merge {
                capabilities_produced: [],
                depends_on: [],
            }
        }
    })

    # Third pass: add capability_skip for capability-skipped cells only.
    let final_cells = ($planned_cells | each {|c|
        if $c.capability_action == "capability-skipped" {
            let worst = (pick-worst-blocker $c.blockers)
            let skip_info = if $worst != null {
                {
                    reason: ($worst.status? | default $c.capability_status | default "capability_blocked"),
                    blocked_capability: ($worst.capability? | default ""),
                    blocked_role: ($worst.role? | default ""),
                    blocked_adapter_key: ($worst.adapter_key? | default ""),
                    rationale: ($worst.rationale? | default (
                        $"($c.cell_id) skipped: ($worst.capability? | default 'unknown') at ($worst.adapter_key? | default '') is ($c.capability_status)"
                    )),
                }
            } else {
                {
                    reason: "capability_blocked",
                    blocked_capability: "",
                    blocked_role: "",
                    blocked_adapter_key: "",
                    rationale: $"($c.cell_id) skipped: capability_status=($c.capability_status)",
                }
            }
            $c | merge {capability_skip: $skip_info}
        } else {
            $c
        }
    })

    {
        schema_version: 1,
        suite_id: $eff_suite_id,
        generated_at: (utc-now),
        cells: $final_cells,
    }
}
