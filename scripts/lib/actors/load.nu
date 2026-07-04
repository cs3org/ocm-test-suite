# Actor tuple loaders.
# Reads optional override files from config/actors/overrides/ and resolves
# platform/account from the matrix SSOT, defaults, and override files.
# File presence means "override exists", not "matrix entry enabled".
# The matrix SSOT is the authoritative source for enumeration.

use ../run/execution-id.nu [validate-matrix-key]
use ./credentials.nu [load-account-credentials]
use ./resolve.nu [resolve-platform resolve-account]
use ../matrix/cell.nu [matrix-entry-state]
use ../matrix/rules-gen.nu [load-matrix-rules matrix-key]
use ../matrix/topology.nu [flow-is-two-party]

def load-actor-defaults [root: string] {
    let path = ($root | path join "config/actors/defaults.nuon")
    if not ($path | path exists) { return null }
    open $path
}

def load-matrix-entry [root: string, flow_id: string, matrix_key: string] {
    let state = (matrix-entry-state $root $flow_id $matrix_key)
    match $state.state {
        "enabled" => {
            let rules = (load-matrix-rules $root)
            $rules.matrix | get $matrix_key
        }
        "disabled" => {
            error make {
                msg: $"Matrix entry '($matrix_key)' is disabled \(enabled: false\). Placeholder cells cannot be run."
            }
        }
        _ => {
            error make {
                msg: $"Matrix entry '($matrix_key)' not in config/matrix/. Known: ($state.known | str join ', ')"
            }
        }
    }
}

export def role-block-has-real-values [role_cfg: record] {
    if ($role_cfg | is-empty) {
        return false
    }
    let platform = ($role_cfg.platform? | default "")
    let account = ($role_cfg.account? | default "")
    (not ($platform | is-empty)) or (not ($account | is-empty))
}

export def assert-file-has-real-overrides [cfg: record, cfg_rel_path: string] {
    let actor_ok = (
        if ($cfg.actor? | default null) == null { false }
        else { role-block-has-real-values ($cfg.actor) }
    )
    let sender_ok = (
        if ($cfg.sender? | default null) == null { false }
        else { role-block-has-real-values ($cfg.sender) }
    )
    let receiver_ok = (
        if ($cfg.receiver? | default null) == null { false }
        else { role-block-has-real-values ($cfg.receiver) }
    )
    if not ($actor_ok or $sender_ok or $receiver_ok) {
        error make {msg: $"Override file '($cfg_rel_path)' has no real overrides \(all role fields empty or missing\). Either add real overrides or remove the file."}
    }
}

def load-role-for-tuple [
    flow_id: string,
    sender_platform: string,
    receiver_platform: string,
    root: string,
    expected_platform: string,
    role: string,
    matrix_platform_fn: closure,
] {
    let mk = (matrix-key $flow_id $sender_platform $receiver_platform)
    validate-matrix-key $mk
    let cfg_path = ($root | path join $"config/actors/overrides/($mk).nuon")
    let cfg_rel_path = $"config/actors/overrides/($mk).nuon"
    let cfg = if ($cfg_path | path exists) {
        let loaded = (open $cfg_path)
        assert-file-has-real-overrides $loaded $cfg_rel_path
        $loaded
    } else {
        {}
    }

    let role_cfg = ($cfg | get --optional $role | default {})
    let cfg_platform = ($role_cfg.platform? | default "")
    let cfg_account = ($role_cfg.account? | default "")

    let matrix = (load-matrix-entry $root $flow_id $mk)
    let eff_flow_id = ($matrix.flow_id? | default $flow_id)
    let matrix_platform = do $matrix_platform_fn $matrix

    let defaults = (load-actor-defaults $root)
    let platform = (resolve-platform $cfg_platform $expected_platform $matrix_platform $role)
    let account = (resolve-account $defaults $eff_flow_id $role $platform $cfg_account $role)
    load-account-credentials $root $platform $account $role
}

export def load-actor-for-tuple [
    flow_id: string,
    sender_platform: string,
    root: string,
    expected_platform: string = "",
]: nothing -> any {
    load-role-for-tuple $flow_id $sender_platform "" $root $expected_platform "actor" {|matrix|
        $matrix.sender?.platform? | default ""
    }
}

export def load-sender-for-tuple [
    flow_id: string,
    sender_platform: string,
    receiver_platform: string,
    root: string,
    expected_platform: string = "",
]: nothing -> any {
    load-role-for-tuple $flow_id $sender_platform $receiver_platform $root $expected_platform "sender" {|matrix|
        $matrix.sender?.platform? | default ""
    }
}

export def load-receiver-for-tuple [
    flow_id: string,
    sender_platform: string,
    receiver_platform: string,
    root: string,
    expected_platform: string = "",
]: nothing -> any {
    let mk = (matrix-key $flow_id $sender_platform $receiver_platform)
    validate-matrix-key $mk
    let matrix = (load-matrix-entry $root $flow_id $mk)
    let eff_flow_id = ($matrix.flow_id? | default $flow_id)

    if not ($eff_flow_id | is-empty) {
        if not (flow-is-two-party $eff_flow_id) {
            return null
        }
    }

    load-role-for-tuple $flow_id $sender_platform $receiver_platform $root $expected_platform "receiver" {|matrix|
        if $matrix.receiver? == null { "" } else { $matrix.receiver.platform? | default "" }
    }
}

export def list-override-files [root: string] {
    let dir = ($root | path join "config/actors/overrides")
    if not ($dir | path exists) { return [] }
    glob ($dir | path join "*.nuon")
    | each {|p| $p | path basename | str replace ".nuon" ""}
    | sort
}

export def list-matrix-keys [root: string] {
    use ../matrix/rules-gen.nu [load-matrix-rules]
    let r = (load-matrix-rules $root)
    $r.matrix
    | transpose name rule
    | where {|x| $x.rule.enabled}
    | get name
    | sort
}
