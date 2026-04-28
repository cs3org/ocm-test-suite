# Shared blocker evaluation helpers, imported by both cell-impl.nu and
# matrix/rules-gen.nu. Must not import from internal.nu or any module that
# transitively imports matrix/rules-gen.nu (to avoid circular imports).

# Worst status across a list of blocker records.
# Precedence (worst -> least): vendor-out-of-scope > vendor-unsupported >
# test-implementation-pending > placeholder. Empty list -> "supported".
# Blockers missing a `status` field (e.g. missing_adapter_bundle,
# missing_capability_entry, unknown_flow_id) are treated as
# "vendor-unsupported" (the data is broken; surface a hard block but not
# out-of-scope).
export def worst-status-of-blockers [blockers: list] {
    if ($blockers | is-empty) { return "supported" }
    let rank = {
        "supported": 0,
        "placeholder": 1,
        "test-implementation-pending": 2,
        "vendor-unsupported": 3,
        "vendor-out-of-scope": 4,
    }
    let statuses = ($blockers | each {|b| $b.status? | default "vendor-unsupported"})
    let ranked = ($statuses | each {|s| $rank | get --optional $s | default 3})
    let max_rank = ($ranked | math max)
    let inv = ($rank | transpose key val | where val == $max_rank | first | get key)
    $inv
}

# Walk one role's required caps and return blocker records for that role.
# Each blocker has {reason_code, role, adapter_key, capability, status?,
# tracking_url?, tracking_note?, rationale?}.
# Optional tracking_url / tracking_note / rationale are only included when the
# adapter capability entry carries a non-null value.
export def derive-role-blockers [
    adapters: record,
    role_caps: list,
    role: string,
    adapter_key: string,
] {
    if ($role_caps | is-empty) { return [] }
    if not ($adapter_key in $adapters) {
        return [{
            reason_code: "missing_adapter_bundle",
            role: $role,
            adapter_key: $adapter_key,
            capability: "",
        }]
    }
    let bundle = ($adapters | get $adapter_key | get capabilities)
    let cap_names = ($bundle | columns)
    mut blockers = []
    for cap in $role_caps {
        if not ($cap in $cap_names) {
            $blockers = ($blockers | append {
                reason_code: "missing_capability_entry",
                role: $role,
                adapter_key: $adapter_key,
                capability: $cap,
            })
        } else {
            let entry = ($bundle | transpose key val | where {|r| $r.key == $cap} | first | get val)
            let status = ($entry.status? | default "supported")
            if $status != "supported" {
                let reason_code = ($status | str replace --all "-" "_")
                mut b = {
                    reason_code: $reason_code,
                    role: $role,
                    adapter_key: $adapter_key,
                    capability: $cap,
                    status: $status,
                }
                let tu = ($entry.tracking_url? | default null)
                let tn = ($entry.tracking_note? | default null)
                let rt = ($entry.rationale? | default null)
                if $tu != null { $b = ($b | upsert tracking_url $tu) }
                if $tn != null { $b = ($b | upsert tracking_note $tn) }
                if $rt != null { $b = ($b | upsert rationale $rt) }
                $blockers = ($blockers | append $b)
            }
        }
    }
    $blockers
}

# Derive requirements and blockers for one cell against the adapter capability
# map and flow capability requirements. Returns {requirements: list, blockers: list}.
#
# Capability keys in the adapters record contain dots (e.g. "share-with.sender"),
# so this function avoids `get $cap` for those lookups and uses `columns` +
# `transpose` instead to prevent Nushell's cell-path traversal from misfiring.
export def derive-cell-impl-info [cell: record, adapters: record, flow_caps: record] {
    let flow_id = $cell.flow_id
    let sender_key = $"($cell.sender_platform)/($cell.sender_version)"

    let flow_entry = ($flow_caps | get --optional $flow_id)
    if $flow_entry == null {
        return {
            requirements: [],
            blockers: [{reason_code: "unknown_flow_id", flow_id: $flow_id, role: "", adapter_key: "", capability: ""}],
        }
    }

    let flow_sender_caps = ($flow_entry.sender? | default [])
    let flow_receiver_caps = ($flow_entry.receiver? | default [])

    let sender_reqs = ($flow_sender_caps | each {|cap| {capability: $cap, role: "sender", adapter_key: $sender_key}})
    let sender_blockers = (derive-role-blockers $adapters $flow_sender_caps "sender" $sender_key)

    let receiver_part = if $cell.is_two_party and not ($flow_receiver_caps | is-empty) {
        let receiver_key = $"($cell.receiver_platform)/($cell.receiver_version)"
        let recv_reqs = ($flow_receiver_caps | each {|cap| {capability: $cap, role: "receiver", adapter_key: $receiver_key}})
        let recv_blocks = (derive-role-blockers $adapters $flow_receiver_caps "receiver" $receiver_key)
        {requirements: $recv_reqs, blockers: $recv_blocks}
    } else {
        {requirements: [], blockers: []}
    }

    {
        requirements: ($sender_reqs | append $receiver_part.requirements),
        blockers: ($sender_blockers | append $receiver_part.blockers),
    }
}
