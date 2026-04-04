# Actor config helpers.
# Reads scenario and platform actor configs from config/actors/.
# Supports defaults inference from config/actors/defaults.nuon and
# platform inference from config/matrix-rules.nuon.

use ./execution-id.nu [validate-path-segment]

# Private: load defaults.nuon or return null if absent.
def load-actor-defaults [root: string] {
    let path = ($root | path join "config/actors/defaults.nuon")
    if not ($path | path exists) { return null }
    open $path
}

# Private: load matrix-rules.nuon entry for a named scenario or null.
def load-matrix-scenario [root: string, scenario: string] {
    let path = ($root | path join "config/matrix-rules.nuon")
    if not ($path | path exists) { return null }
    let rules = (open $path)
    $rules.scenarios | get --optional $scenario
}

# Private: resolve platform from cfg value, expected caller arg, or matrix fallback.
# Errors if cfg_platform mismatches expected_platform.
# Errors if none of the three sources provides a non-empty value.
def resolve-platform [
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

# Private: resolve account from cfg or defaults lookup; error if neither resolves.
# role_key must match the key used in defaults.nuon flows (actor, sender, or receiver).
def resolve-account [
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

# Private: load and validate account credentials from a platform config file.
def load-account-credentials [root: string, platform: string, account_name: string, label: string] {
    if ($platform | is-empty) {
        error make {msg: $"($label) platform is empty"}
    }
    if ($account_name | is-empty) {
        error make {msg: $"($label) account is empty"}
    }
    validate-path-segment $platform $"($label).platform"
    validate-path-segment $account_name $"($label).account"

    let platform_cfg_path = ($root | path join $"config/actors/platforms/($platform).nuon")
    if not ($platform_cfg_path | path exists) {
        error make {msg: $"Actor platform config not found: config/actors/platforms/($platform).nuon"}
    }
    let platform_cfg = (open $platform_cfg_path)

    if ($platform_cfg.accounts? == null) {
        error make {msg: $"Platform config '($platform).nuon' missing accounts record"}
    }
    let account = ($platform_cfg.accounts | get --optional $account_name)
    if $account == null {
        error make {msg: $"Actor account '($account_name)' not found in platform '($platform)' config [role: ($label)]"}
    }

    if ($account.username? | default "" | is-empty) {
        error make {msg: $"Actor account '($account_name)' on '($platform)' has empty username [role: ($label)]"}
    }
    if ($account.password? | default "" | is-empty) {
        error make {msg: $"Actor account '($account_name)' on '($platform)' has empty password [role: ($label)]"}
    }

    {
        platform: $platform,
        account: $account_name,
        username: $account.username,
        password: $account.password,
    }
}

# Load actor credentials for a one-party scenario (actor field).
# Returns null when no scenario actor config file exists.
# expected_platform: if non-empty, used when scenario file omits platform,
#   and checked for mismatch if scenario file also provides one.
# Errors on: platform mismatch, platform cannot be inferred, account cannot
#   be resolved, missing platform config, empty username/password.
export def load-actor-for-scenario [
    scenario: string,
    root: string,
    expected_platform: string = "",
]: nothing -> any {
    validate-path-segment $scenario "scenario"
    let cfg_path = ($root | path join $"config/actors/scenarios/($scenario).nuon")
    if not ($cfg_path | path exists) { return null }
    let scenario_cfg = (open $cfg_path)

    let role_cfg = ($scenario_cfg.actor? | default {})
    let cfg_platform = ($role_cfg.platform? | default "")
    let cfg_account = ($role_cfg.account? | default "")

    let matrix = (load-matrix-scenario $root $scenario)
    let matrix_platform = (if $matrix == null { "" } else { $matrix.sender?.platform? | default "" })
    let flow_id = (if $matrix == null { "" } else { $matrix.flow_id? | default "" })

    let defaults = (load-actor-defaults $root)
    let platform = (resolve-platform $cfg_platform $expected_platform $matrix_platform "actor")
    let account = (resolve-account $defaults $flow_id "actor" $platform $cfg_account "actor")
    load-account-credentials $root $platform $account "actor"
}

# Load sender credentials for a scenario.
# Supports both one-party shape (actor field) and two-party shape (sender field).
# Returns null when no scenario file exists or no sender/actor field is present.
# expected_platform: if non-empty, used when scenario file omits platform,
#   and checked for mismatch if scenario file also provides one.
export def load-sender-for-scenario [
    scenario: string,
    root: string,
    expected_platform: string = "",
]: nothing -> any {
    validate-path-segment $scenario "scenario"
    let cfg_path = ($root | path join $"config/actors/scenarios/($scenario).nuon")
    if not ($cfg_path | path exists) { return null }
    let cfg = (open $cfg_path)

    # Two-party uses sender field; one-party uses actor field as fallback.
    let has_sender = ($cfg.sender? != null)
    let raw_role_cfg = if $has_sender { $cfg.sender } else { $cfg.actor? }
    if $raw_role_cfg == null { return null }

    let role_cfg = $raw_role_cfg
    let role_key = if $has_sender { "sender" } else { "actor" }
    let cfg_platform = ($role_cfg.platform? | default "")
    let cfg_account = ($role_cfg.account? | default "")

    let matrix = (load-matrix-scenario $root $scenario)
    let matrix_platform = (if $matrix == null { "" } else { $matrix.sender?.platform? | default "" })
    let flow_id = (if $matrix == null { "" } else { $matrix.flow_id? | default "" })

    let defaults = (load-actor-defaults $root)
    let platform = (resolve-platform $cfg_platform $expected_platform $matrix_platform "sender")
    let account = (resolve-account $defaults $flow_id $role_key $platform $cfg_account "sender")
    load-account-credentials $root $platform $account "sender"
}

# Load receiver credentials for a two-party scenario (receiver field).
# Returns null when no receiver field exists (one-party scenario).
# expected_platform: if non-empty, used when scenario file omits platform,
#   and checked for mismatch if scenario file also provides one.
export def load-receiver-for-scenario [
    scenario: string,
    root: string,
    expected_platform: string = "",
]: nothing -> any {
    validate-path-segment $scenario "scenario"
    let cfg_path = ($root | path join $"config/actors/scenarios/($scenario).nuon")
    if not ($cfg_path | path exists) { return null }
    let cfg = (open $cfg_path)

    let role_cfg = $cfg.receiver?
    if $role_cfg == null { return null }

    let cfg_platform = ($role_cfg.platform? | default "")
    let cfg_account = ($role_cfg.account? | default "")

    let matrix = (load-matrix-scenario $root $scenario)
    let matrix_platform = (if $matrix == null { "" } else {
        if $matrix.receiver? == null { "" } else { $matrix.receiver.platform? | default "" }
    })
    let flow_id = (if $matrix == null { "" } else { $matrix.flow_id? | default "" })

    let defaults = (load-actor-defaults $root)
    let platform = (resolve-platform $cfg_platform $expected_platform $matrix_platform "receiver")
    let account = (resolve-account $defaults $flow_id "receiver" $platform $cfg_account "receiver")
    load-account-credentials $root $platform $account "receiver"
}

# List scenario names that have actor config files.
export def list-scenario-names [root: string] {
    let dir = ($root | path join "config/actors/scenarios")
    if not ($dir | path exists) { return [] }
    glob ($dir | path join "*.nuon")
    | each {|p| $p | path basename | str replace ".nuon" ""}
    | sort
}

# Validate actor config for a scenario; errors readably when anything is wrong.
# Detects one-party (actor field) vs two-party (sender/receiver fields) automatically.
# When sender_platform is non-empty, passes it into loader for inference and mismatch check.
# When receiver_platform is non-empty (two-party only), passes it into loader similarly.
export def validate-actor-config [
    scenario: string,
    root: string,
    sender_platform: string = "",
    receiver_platform: string = "",
] {
    let cfg_path = ($root | path join $"config/actors/scenarios/($scenario).nuon")
    if not ($cfg_path | path exists) {
        error make {msg: $"No actor config for scenario '($scenario)': config/actors/scenarios/($scenario).nuon not found"}
    }
    let cfg = (open $cfg_path)
    let is_two_party = (($cfg.sender? != null) and ($cfg.actor? == null))

    if $is_two_party {
        let sender = (load-sender-for-scenario $scenario $root $sender_platform)
        if $sender == null {
            error make {msg: $"Sender actor config not found for scenario '($scenario)'"}
        }
        let receiver = (load-receiver-for-scenario $scenario $root $receiver_platform)
        if $receiver == null {
            error make {msg: $"Receiver actor config not found for scenario '($scenario)'"}
        }
    } else {
        let a = (load-actor-for-scenario $scenario $root $sender_platform)
        if $a == null {
            error make {msg: $"No actor config for scenario '($scenario)': config/actors/scenarios/($scenario).nuon not found"}
        }
    }
}
