# Actor scenario loaders.
# Reads optional override files from config/actors/scenarios/ and resolves
# platform/account from the matrix SSOT, defaults, and override files.
# File presence means "override exists", not "scenario enabled".
# The matrix SSOT is the authoritative source for enumeration.

use ../run/execution-id.nu [validate-path-segment]
use ./credentials.nu [load-account-credentials]
use ./resolve.nu [resolve-platform resolve-account]
use ../matrix/rules-gen.nu [load-matrix-rules]
use ../matrix/topology.nu [flow-is-two-party]

# Private: load defaults.nuon or return null if absent.
def load-actor-defaults [root: string] {
    let path = ($root | path join "config/actors/defaults.nuon")
    if not ($path | path exists) { return null }
    open $path
}

# Private: load matrix SSOT entry for a named scenario or null.
def load-matrix-scenario [root: string, scenario: string] {
    let rules = (load-matrix-rules $root)
    $rules.scenarios | get --optional $scenario
}

# Private: when the override file is present, assert it has at least one
# non-empty role field (actor, sender, or receiver). Empty override files
# produce confusing silent no-ops; this turns them into a clear error.
def assert-file-has-real-overrides [cfg: record, cfg_rel_path: string] {
    let actor_ok = (($cfg.actor? | default {} | is-empty) == false)
    let sender_ok = (($cfg.sender? | default {} | is-empty) == false)
    let receiver_ok = (($cfg.receiver? | default {} | is-empty) == false)
    if not ($actor_ok or $sender_ok or $receiver_ok) {
        error make {msg: $"Override file '($cfg_rel_path)' has no real overrides \(all role fields empty or missing\). Either add real overrides or remove the file."}
    }
}

# Load actor credentials for a one-party scenario (actor field).
# Resolves via matrix + defaults when no override file is present.
# expected_platform: if non-empty, used when the override file omits
#   platform, and checked for mismatch if the override also provides one.
# Errors on: platform mismatch, platform cannot be inferred, account cannot
#   be resolved, missing platform config, empty username/password.
export def load-actor-for-scenario [
    scenario: string,
    root: string,
    expected_platform: string = "",
]: nothing -> any {
    validate-path-segment $scenario "scenario"
    let cfg_path = ($root | path join $"config/actors/scenarios/($scenario).nuon")
    let cfg_rel_path = $"config/actors/scenarios/($scenario).nuon"
    let cfg = if ($cfg_path | path exists) {
        let loaded = (open $cfg_path)
        assert-file-has-real-overrides $loaded $cfg_rel_path
        $loaded
    } else {
        {}
    }

    let role_cfg = ($cfg.actor? | default {})
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

# Load sender credentials for a two-party scenario (sender field).
# Resolves via matrix + defaults when no override file is present.
# expected_platform: if non-empty, used when the override file omits
#   platform, and checked for mismatch if the override also provides one.
export def load-sender-for-scenario [
    scenario: string,
    root: string,
    expected_platform: string = "",
]: nothing -> any {
    validate-path-segment $scenario "scenario"
    let cfg_path = ($root | path join $"config/actors/scenarios/($scenario).nuon")
    let cfg_rel_path = $"config/actors/scenarios/($scenario).nuon"
    let cfg = if ($cfg_path | path exists) {
        let loaded = (open $cfg_path)
        assert-file-has-real-overrides $loaded $cfg_rel_path
        $loaded
    } else {
        {}
    }

    let role_cfg = ($cfg.sender? | default {})
    let cfg_platform = ($role_cfg.platform? | default "")
    let cfg_account = ($role_cfg.account? | default "")

    let matrix = (load-matrix-scenario $root $scenario)
    let matrix_platform = (if $matrix == null { "" } else { $matrix.sender?.platform? | default "" })
    let flow_id = (if $matrix == null { "" } else { $matrix.flow_id? | default "" })

    let defaults = (load-actor-defaults $root)
    let platform = (resolve-platform $cfg_platform $expected_platform $matrix_platform "sender")
    let account = (resolve-account $defaults $flow_id "sender" $platform $cfg_account "sender")
    load-account-credentials $root $platform $account "sender"
}

# Load receiver credentials for a two-party scenario (receiver field).
# Returns null when the matrix says the flow is one-party; the caller does
# not need a receiver for one-party flows.
# expected_platform: if non-empty, used when the override file omits
#   platform, and checked for mismatch if the override also provides one.
export def load-receiver-for-scenario [
    scenario: string,
    root: string,
    expected_platform: string = "",
]: nothing -> any {
    validate-path-segment $scenario "scenario"
    let cfg_path = ($root | path join $"config/actors/scenarios/($scenario).nuon")
    let cfg_rel_path = $"config/actors/scenarios/($scenario).nuon"
    let cfg = if ($cfg_path | path exists) {
        let loaded = (open $cfg_path)
        assert-file-has-real-overrides $loaded $cfg_rel_path
        $loaded
    } else {
        {}
    }

    let matrix = (load-matrix-scenario $root $scenario)
    let flow_id = (if $matrix == null { "" } else { $matrix.flow_id? | default "" })

    # Matrix is SSOT for topology. If flow_id is known, derive it from the
    # canonical flow file. If the matrix doesn't know this scenario, fall
    # through so resolve-platform/resolve-account produce informative errors.
    if not ($flow_id | is-empty) {
        if not (flow-is-two-party $flow_id) {
            return null
        }
    }

    let role_cfg = ($cfg.receiver? | default {})
    let cfg_platform = ($role_cfg.platform? | default "")
    let cfg_account = ($role_cfg.account? | default "")

    let matrix_platform = (if $matrix == null { "" } else {
        if $matrix.receiver? == null { "" } else { $matrix.receiver.platform? | default "" }
    })

    let defaults = (load-actor-defaults $root)
    let platform = (resolve-platform $cfg_platform $expected_platform $matrix_platform "receiver")
    let account = (resolve-account $defaults $flow_id "receiver" $platform $cfg_account "receiver")
    load-account-credentials $root $platform $account "receiver"
}

# List scenario basenames that have an override file in config/actors/scenarios/.
# File presence means "override exists", not "scenario enabled".
# Use list-matrix-scenarios to enumerate the enabled set from the matrix SSOT.
export def list-override-files [root: string] {
    let dir = ($root | path join "config/actors/scenarios")
    if not ($dir | path exists) { return [] }
    glob ($dir | path join "*.nuon")
    | each {|p| $p | path basename | str replace ".nuon" ""}
    | sort
}

# List scenario names enabled in the matrix SSOT (the authoritative source).
export def list-matrix-scenarios [root: string] {
    use ../matrix/rules-gen.nu [load-matrix-rules]
    let r = (load-matrix-rules $root)
    $r.scenarios
    | transpose name rule
    | where {|x| $x.rule.enabled}
    | get name
    | sort
}
