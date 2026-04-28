# Platform completeness check.

# Returns {missing_from_json, extra_in_json}.
# missing_from_json: adapter keys declared in platforms config but absent
#   from the JSON adapter set.
# extra_in_json: adapter keys in JSON that are not declared in platforms
#   config.
export def check-platform-completeness [
    ocmts_root: string,
    adapter_keys: list<string>,
] {
    let platforms_path = ($ocmts_root | path join "config/matrix/platforms.nuon")
    if not ($platforms_path | path exists) {
        error make {msg: $"config/matrix/platforms.nuon: not found"}
    }
    let cfg = (open $platforms_path)
    if $cfg.schema_version != 1 {
        error make {msg: $"config/matrix/platforms.nuon: expected schema_version 1, got ($cfg.schema_version)"}
    }
    let declared = ($cfg.platforms | transpose name entry | each {|row|
        $row.entry.version_lines | each {|v| $"($row.name)/($v)"}
    } | flatten | sort)

    let missing_from_json = ($declared | where {|x| not ($x in $adapter_keys)} | sort)
    let extra_in_json = ($adapter_keys | where {|x| not ($x in $declared)} | sort)
    {missing_from_json: $missing_from_json, extra_in_json: $extra_in_json}
}
