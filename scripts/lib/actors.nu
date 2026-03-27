# Actor config helpers.
# Reads scenario and platform actor configs from config/actors/.

use ./execution-id.nu [validate-path-segment]

# Load actor credentials for a scenario.
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
    validate-path-segment $platform "actor.platform"
    validate-path-segment $account_name "actor.account"

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
        error make {msg: $"Actor account '($account_name)' not found in platform '($platform)' config"}
    }

    if ($account.username? | default "" | is-empty) {
        error make {msg: $"Actor account '($account_name)' on '($platform)' has empty username"}
    }
    if ($account.password? | default "" | is-empty) {
        error make {msg: $"Actor account '($account_name)' on '($platform)' has empty password"}
    }

    {
        platform: $platform,
        account: $account_name,
        username: $account.username,
        password: $account.password,
    }
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
# Shares the same checks as compose actor validation: scenario file exists,
# platform config exists, account exists, username/password non-empty.
# When sender_platform is non-empty, also checks actor platform matches.
export def validate-actor-config [
    scenario: string,
    root: string,
    sender_platform: string = "",
] {
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
