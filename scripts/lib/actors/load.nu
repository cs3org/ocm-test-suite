# Actor scenario loaders.
# Reads scenario actor config files from config/actors/scenarios/ and
# resolves platform/account from config, matrix rules, and defaults.

use ../run/execution-id.nu [validate-path-segment]
use ./credentials.nu [load-account-credentials]
use ./resolve.nu [resolve-platform resolve-account]

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
