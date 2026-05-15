# Platform and account precedence resolvers.

# Resolve platform from cfg value, expected caller arg, or matrix fallback.
# Errors if cfg_platform mismatches expected_platform.
# Errors if none of the three sources provides a non-empty value.
export def resolve-platform [
    cfg_platform: string,
    expected_platform: string,
    matrix_platform: string,
    label: string,
] {
    if (not ($cfg_platform | is-empty)) and (not ($expected_platform | is-empty)) {
        if $cfg_platform != $expected_platform {
            error make {msg: $"($label) platform '($cfg_platform)' in scenario config mismatches expected '($expected_platform)'"}
        }
    }
    if not ($cfg_platform | is-empty) { return $cfg_platform }
    if not ($expected_platform | is-empty) { return $expected_platform }
    if not ($matrix_platform | is-empty) { return $matrix_platform }
    error make {msg: $"Cannot infer ($label) platform: scenario file omits platform, no expected platform provided, and no matrix rule found for this scenario"}
}

# Resolve account from cfg or defaults lookup; error if neither resolves.
# role_key must match the key used in defaults.nuon flows (actor, sender, or receiver).
export def resolve-account [
    defaults: any,
    flow_id: string,
    role_key: string,
    platform: string,
    cfg_account: string,
    label: string,
] {
    if not ($cfg_account | is-empty) { return $cfg_account }
    if $defaults == null {
        error make {msg: $"($label) account not in scenario config and no defaults file found at config/actors/defaults.nuon"}
    }
    if ($flow_id | is-empty) {
        error make {msg: $"($label) account not in scenario config and cannot look up defaults: flow_id unknown (no matrix rule for this scenario)"}
    }
    let flow_entry = ($defaults.flows? | default {} | get --optional $flow_id)
    if $flow_entry == null {
        error make {msg: $"($label) account not in scenario config and defaults have no entry for flow '($flow_id)'"}
    }
    let role_entry = ($flow_entry | get --optional $role_key)
    if $role_entry == null {
        error make {msg: $"($label) account not in scenario config and defaults have no entry for flow '($flow_id)', role '($role_key)'"}
    }
    let by_platform = ($role_entry.by_platform? | default {})
    let acct = ($by_platform | get --optional $platform)
    if $acct == null {
        error make {msg: $"($label) account not in scenario config and defaults have no mapping for flow '($flow_id)', role '($role_key)', platform '($platform)'"}
    }
    $acct
}
