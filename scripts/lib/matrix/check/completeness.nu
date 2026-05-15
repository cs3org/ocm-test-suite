# Per-adapter capability completeness check.

# Reads canonical capability list from config/matrix/capabilities.v1.nuon.
# Returns {canonical: [...], missing: [{adapter_key, capability_key}, ...]}.
# missing: entries where an adapter's capabilities object lacks a key
#   that appears in the canonical list.
export def check-capability-completeness [
    ocmts_root: string,
    adapters: record,
] {
    let caps_path = ($ocmts_root | path join "config/matrix/capabilities.v1.nuon")
    if not ($caps_path | path exists) {
        error make {msg: $"config/matrix/capabilities.v1.nuon: not found"}
    }
    let cfg = (open $caps_path)
    if $cfg.schema_version != 1 {
        error make {msg: $"config/matrix/capabilities.v1.nuon: expected schema_version 1, got ($cfg.schema_version)"}
    }
    let canonical = $cfg.capabilities

    let missing = ($adapters | transpose adapter_key entry | each {|row|
        let cap_keys = ($row.entry.capabilities | columns)
        $canonical | each {|cap|
            if not ($cap in $cap_keys) {
                {adapter_key: $row.adapter_key, capability_key: $cap}
            }
        } | compact
    } | flatten | sort-by adapter_key capability_key)

    {canonical: $canonical, missing: $missing}
}
