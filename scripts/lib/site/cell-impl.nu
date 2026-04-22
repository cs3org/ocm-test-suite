# Cell implementation info: expand matrix cells and evaluate adapter capabilities.

use ./internal.nu [now-utc compute-matrix-cells]

# Derive requirements and blockers for one cell against the adapter capability
# map. Returns {requirements: list, blockers: list}.
export def derive-cell-impl-info [cell: record, adapters: record] {
    let flow_id = $cell.flow_id
    let sender_key = $"($cell.sender_platform)/($cell.sender_version)"

    let flow_sender_caps = if $flow_id == "login" {
        ["login"]
    } else if $flow_id == "share-with" {
        ["login", "share-with.sender"]
    } else if $flow_id == "contact-token" {
        ["login", "contact-token.sender", "share-with.sender"]
    } else if $flow_id == "contact-wayf" {
        ["login", "contact-wayf.sender", "share-with.sender"]
    } else {
        null
    }

    if $flow_sender_caps == null {
        return {
            requirements: [],
            blockers: [{reason_code: "unknown_flow_id", flow_id: $flow_id, role: "", adapter_key: "", capability: ""}],
        }
    }

    mut requirements = []
    mut blockers = []

    if $sender_key in $adapters {
        let sender_caps = ($adapters | get $sender_key)
        for cap in $flow_sender_caps {
            $requirements = ($requirements | append {capability: $cap, role: "sender", adapter_key: $sender_key})
            if not ($cap in $sender_caps) {
                $blockers = ($blockers | append {reason_code: "missing_capability", role: "sender", adapter_key: $sender_key, capability: $cap})
            }
        }
    } else {
        for cap in $flow_sender_caps {
            $requirements = ($requirements | append {capability: $cap, role: "sender", adapter_key: $sender_key})
        }
        $blockers = ($blockers | append {reason_code: "missing_adapter_bundle", role: "sender", adapter_key: $sender_key, capability: ""})
    }

    if $cell.is_two_party {
        let receiver_key = $"($cell.receiver_platform)/($cell.receiver_version)"
        let flow_receiver_caps = if $flow_id == "share-with" {
            ["login", "share-with.receiver"]
        } else if $flow_id == "contact-token" {
            ["login", "contact-token.receiver", "provider-identity", "share-with.receiver"]
        } else if $flow_id == "contact-wayf" {
            ["login", "contact-wayf.receiver", "provider-identity", "share-with.receiver"]
        } else {
            []
        }
        if not ($flow_receiver_caps | is-empty) {
            if $receiver_key in $adapters {
                let receiver_caps = ($adapters | get $receiver_key)
                for cap in $flow_receiver_caps {
                    $requirements = ($requirements | append {capability: $cap, role: "receiver", adapter_key: $receiver_key})
                    if not ($cap in $receiver_caps) {
                        $blockers = ($blockers | append {reason_code: "missing_capability", role: "receiver", adapter_key: $receiver_key, capability: $cap})
                    }
                }
            } else {
                for cap in $flow_receiver_caps {
                    $requirements = ($requirements | append {capability: $cap, role: "receiver", adapter_key: $receiver_key})
                }
                $blockers = ($blockers | append {reason_code: "missing_adapter_bundle", role: "receiver", adapter_key: $receiver_key, capability: ""})
            }
        }
    }

    {requirements: $requirements, blockers: $blockers}
}

# Build implemented-cells.v1.json content.
# Evaluates each matrix cell (including disabled) against the adapter
# capability map and produces a structured record keyed by cell_id.
export def build-implemented-cells-json [rules: record, rules_path: string, cap_map_path: string] {
    let cap_map = (open $cap_map_path)
    let adapters = ($cap_map.adapters? | default {})
    let cell_list = (compute-matrix-cells $rules)
    let cells = if ($cell_list | is-empty) {
        {}
    } else {
        ($cell_list | each {|c|
            let impl_info = (derive-cell-impl-info $c $adapters)
            {
                ($c.cell_id): {
                    scenario: $c.scenario,
                    flow_id: $c.flow_id,
                    pair: $c.pair,
                    browser: $c.browser,
                    sender_platform: $c.sender_platform,
                    sender_version: $c.sender_version,
                    receiver_platform: $c.receiver_platform,
                    receiver_version: $c.receiver_version,
                    artifact_name: $c.artifact_name,
                    mitm: $c.mitm,
                    implemented: ($impl_info.blockers | is-empty),
                    requirements: $impl_info.requirements,
                    blockers: $impl_info.blockers,
                }
            }
        } | into record)
    }
    {
        schema_version: 1,
        generated_at: (now-utc),
        sources: {
            matrix_rules_path: $rules_path,
            capability_map_path: $cap_map_path,
        },
        cells: $cells,
    }
}
