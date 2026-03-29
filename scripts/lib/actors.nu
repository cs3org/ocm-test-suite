# Actor config helpers.
# Reads scenario and platform actor configs from config/actors/.

use ./execution-id.nu [validate-path-segment]

# Private: load and validate account credentials from a platform config file.
def load-account-credentials [root: string, platform: string, account_name: string, label: string] {
    if ($platform | is-empty) {
        error make {msg: $"Scenario config missing ($label).platform"}
    }
    if ($account_name | is-empty) {
        error make {msg: $"Scenario config missing ($label).account"}
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
# Errors on: invalid slug, missing platform config, missing account, empty username/password.
# Returns full credentials including password (test-only platform; no secrets).
export def load-actor-for-scenario [
    scenario: string,
    root: string,
]: nothing -> any {
    validate-path-segment $scenario "scenario"
    let cfg_path = ($root | path join $"config/actors/scenarios/($scenario).nuon")
    if not ($cfg_path | path exists) {
        return null
    }
    let scenario_cfg = (open $cfg_path)

    let platform = ($scenario_cfg.actor?.platform? | default "")
    let account_name = ($scenario_cfg.actor?.account? | default "")
    if ($platform | is-empty) {
        error make {msg: $"Scenario config '($scenario).nuon' missing actor.platform"}
    }
    if ($account_name | is-empty) {
        error make {msg: $"Scenario config '($scenario).nuon' missing actor.account"}
    }
    load-account-credentials $root $platform $account_name "actor"
}

# Load sender credentials for a scenario.
# Supports both one-party shape (actor field) and two-party shape (sender field).
# Returns null when no scenario file exists or no sender/actor field is present.
export def load-sender-for-scenario [
    scenario: string,
    root: string,
]: nothing -> any {
    validate-path-segment $scenario "scenario"
    let cfg_path = ($root | path join $"config/actors/scenarios/($scenario).nuon")
    if not ($cfg_path | path exists) { return null }
    let cfg = (open $cfg_path)
    # Two-party uses sender field; one-party uses actor field.
    let role_cfg = if $cfg.sender? != null {
        $cfg.sender
    } else {
        $cfg.actor?
    }
    if $role_cfg == null { return null }
    let platform = ($role_cfg.platform? | default "")
    let account_name = ($role_cfg.account? | default "")
    load-account-credentials $root $platform $account_name "sender"
}

# Load receiver credentials for a two-party scenario (receiver field).
# Returns null when no receiver field exists (one-party scenario).
export def load-receiver-for-scenario [
    scenario: string,
    root: string,
]: nothing -> any {
    validate-path-segment $scenario "scenario"
    let cfg_path = ($root | path join $"config/actors/scenarios/($scenario).nuon")
    if not ($cfg_path | path exists) { return null }
    let cfg = (open $cfg_path)
    let role_cfg = $cfg.receiver?
    if $role_cfg == null { return null }
    let platform = ($role_cfg.platform? | default "")
    let account_name = ($role_cfg.account? | default "")
    load-account-credentials $root $platform $account_name "receiver"
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
# When sender_platform is non-empty, also checks sender platform matches.
# When receiver_platform is non-empty (two-party only), also checks receiver platform matches.
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
        let sender = (load-sender-for-scenario $scenario $root)
        if $sender == null {
            error make {msg: $"Sender actor config not found for scenario '($scenario)'"}
        }
        if not ($sender_platform | is-empty) {
            if $sender.platform != $sender_platform {
                error make {msg: $"Sender platform '($sender.platform)' does not match expected '($sender_platform)'"}
            }
        }
        let receiver = (load-receiver-for-scenario $scenario $root)
        if $receiver == null {
            error make {msg: $"Receiver actor config not found for scenario '($scenario)'"}
        }
        if not ($receiver_platform | is-empty) {
            if $receiver.platform != $receiver_platform {
                error make {msg: $"Receiver platform '($receiver.platform)' does not match expected '($receiver_platform)'"}
            }
        }
    } else {
        let a = (load-actor-for-scenario $scenario $root)
        if $a == null {
            error make {msg: $"No actor config for scenario '($scenario)': config/actors/scenarios/($scenario).nuon not found"}
        }
        if not ($sender_platform | is-empty) {
            if $a.platform != $sender_platform {
                error make {msg: $"Actor platform '($a.platform)' does not match sender platform '($sender_platform)'"}
            }
        }
    }
}
