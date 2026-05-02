# Capability-name drift check: scans flow files, collects names used
# in flows and adapters, asserts subset of canonical capability list.

# Roleless capabilities: intentionally one-party operations without a role suffix.
# Any new roleless capability must be added here AND documented in
# config/matrix/capabilities.v1.nuon with a rationale.
const ROLELESS_CAPABILITY_ALLOWLIST = [
    "flow.login"
    "op.login"
    "op.provider-identity"
]

# Validate that a capability name follows the flow.X.role or op.X.role convention.
# Roleless names in ROLELESS_CAPABILITY_ALLOWLIST are explicitly allowed.
# Returns null when valid, or an error string when not.
export def validate-capability-name-shape [cap: string] {
    if ($cap in $ROLELESS_CAPABILITY_ALLOWLIST) { return null }
    let parts = ($cap | split row ".")
    if ($parts | length) < 3 {
        $"capability '($cap)' violates the flow.X.role / op.X.role contract; allowed roleless exceptions: ($ROLELESS_CAPABILITY_ALLOWLIST | str join ', '). If you need to add a new one-party capability, update the allowlist in scripts/lib/matrix/check/flow-drift.nu and document the rationale in config/matrix/capabilities.v1.nuon."
    } else {
        null
    }
}

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

    # Check name shape violations (roleless names not in the allowlist).
    let shape_violations = ($canonical | each {|c| validate-capability-name-shape $c} | compact)

    {unknown_names: $unknown_names, shape_violations: $shape_violations}
}
