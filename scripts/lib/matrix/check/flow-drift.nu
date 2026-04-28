# Capability-name drift check: scans flow files, collects names used
# in flows and adapters, asserts subset of canonical capability list.

export def check-capability-name-drift [
    ocmts_root: string,
    canonical: list<string>,
    adapter_cap_keys: list<string>,
] {
    let flows_dir = ($ocmts_root | path join "config/matrix/flows")
    if not ($flows_dir | path exists) {
        error make {msg: $"config/matrix/flows: directory not found"}
    }
    let flow_files = (glob ($flows_dir | path join "*.nuon") | sort)

    mut used_in_flows = []
    for $f in $flow_files {
        let flow = (open $f)
        let req = ($flow.required_capabilities? | default {})
        let sender = ($req.sender? | default [])
        let receiver = ($req.receiver? | default [])
        $used_in_flows = ($used_in_flows | append $sender | append $receiver)
    }

    let all_used = (($used_in_flows | append $adapter_cap_keys) | uniq | sort)
    let unknown_names = ($all_used | where {|c| not ($c in $canonical)} | sort)
    {unknown_names: $unknown_names}
}
