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

const LOGIN_MECHANISMS = ["same-origin", "external-idp"]

# Strict validation of the per-platform login block in platforms.nuon.
# Every platform must declare login.mechanism from LOGIN_MECHANISMS; an
# external-idp platform must also declare a non-empty realm.
# Returns {violations: list<string>}.
export def check-platform-login [ocmts_root: string] {
    let platforms_path = ($ocmts_root | path join "config/matrix/platforms.nuon")
    if not ($platforms_path | path exists) {
        error make {msg: $"config/matrix/platforms.nuon: not found"}
    }
    let cfg = (open $platforms_path)
    mut violations = []
    for row in ($cfg.platforms | transpose name entry) {
        let name = $row.name
        let login = ($row.entry | get --optional login)
        if $login == null {
            $violations = ($violations | append $"($name): missing required 'login' block")
            continue
        }
        let mechanism = ($login | get --optional mechanism)
        if not ($mechanism in $LOGIN_MECHANISMS) {
            $violations = ($violations | append $"($name): login.mechanism must be one of [(($LOGIN_MECHANISMS | str join ', '))]; got ($mechanism)")
            continue
        }
        if $mechanism == "external-idp" {
            let realm = ($login | get --optional realm | default "")
            if ($realm | is-empty) {
                $violations = ($violations | append $"($name): external-idp login requires a non-empty 'realm'")
            }
        }
    }
    {violations: $violations}
}
