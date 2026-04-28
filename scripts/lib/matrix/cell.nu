# Compute deterministic cell and artifact identifiers.

use ../run/execution-id.nu [validate-path-segment]
use ../domain/core/ocmts-root.nu [get-ocmts-root]
use ../run/flow-ids.nu [PUBLIC_FLOW_IDS]
use ./topology.nu [assert-topology-matches]
use ./rules-gen.nu [load-matrix-rules]

# Error if scenario.enabled != true in the matrix SSOT under config/matrix/.
# Call from run entrypoints to reject placeholder scenarios early.
# Does not affect matrix cell (which must work for all scenarios).
export def assert-scenario-enabled [scenario: string] {
    let root = get-ocmts-root
    let rules = (load-matrix-rules $root)
    let known_scenarios = ($rules.scenarios | columns)
    if not ($scenario in $known_scenarios) {
        error make {msg: $"Scenario '($scenario)' not in config/matrix/. Known: ($known_scenarios | str join ', ')"}
    }
    let sc = ($rules.scenarios | get $scenario)
    let enabled = ($sc.enabled? | default false)
    if not $enabled {
        error make {msg: $"Scenario '($scenario)' is disabled \(enabled: false\). Placeholder scenarios cannot be run."}
    }
}

# Validate browser against the supported allowlist.
# Only chrome is supported. Error message is readable.
export def validate-browser [browser: string] {
    let allowed = ["chrome"]
    if not ($browser in $allowed) {
        error make {msg: $"browser '($browser)' not in supported list: ($allowed | str join ', ')"}
    }
    $browser
}

# Compute cell_id and artifact_name for one-party or two-party scenarios.
# One-party (no receiver): cell_id = "login__nextcloud-v33"
# Two-party (with receiver): cell_id = "share-with__nextcloud-v33__nextcloud-v33"
# flow_id defaults to scenario when not supplied (e.g. main down path).
# scenario_module is derived from effective_flow_id so Cypress module selection
# follows the flow, not the scenario key. scenario is the raw scenario key for
# UI and manifest use.
# Emits: flow_id, scenario_module, scenario, cell_id, artifact_name,
#        participant fields, is_two_party, browser.
export def compute-cell [
    scenario: string,
    sender_platform: string,
    sender_version: string,
    browser: string,
    receiver_platform: string = "",
    receiver_version: string = "",
    flow_id: string = "",
] {
    let effective_flow_id = if ($flow_id | is-empty) { $scenario } else { $flow_id }
    let fid = (validate-path-segment $effective_flow_id "flow_id")
    let scenario_module = $fid
    let sc_key = (validate-path-segment $scenario "scenario")
    let p = (validate-path-segment $sender_platform "sender_platform")
    let v = (validate-path-segment $sender_version "sender_version")
    let b = (validate-browser $browser)
    let is_two_party = (not ($receiver_platform | is-empty))
    assert-topology-matches $effective_flow_id $is_two_party "compute-cell args (receiver_platform empty=one-party, present=two-party)"
    if $is_two_party {
        let rp = (validate-path-segment $receiver_platform "receiver_platform")
        let rv = (validate-path-segment $receiver_version "receiver_version")
        {
            flow_id: $fid,
            scenario_module: $scenario_module,
            scenario: $sc_key,
            cell_id: $"($fid)__($p)-($v)__($rp)-($rv)",
            artifact_name: $"cell-($fid)-($p)-($v)-($rp)-($rv)",
            pair: $"($p)-($v)-($rp)-($rv)",
            sender_platform: $p,
            sender_version: $v,
            receiver_platform: $rp,
            receiver_version: $rv,
            browser: $b,
            is_two_party: true,
        }
    } else {
        {
            flow_id: $fid,
            scenario_module: $scenario_module,
            scenario: $sc_key,
            cell_id: $"($fid)__($p)-($v)",
            artifact_name: $"cell-($fid)-($p)-($v)",
            pair: $"($p)-($v)",
            sender_platform: $p,
            sender_version: $v,
            receiver_platform: "",
            receiver_version: "",
            browser: $b,
            is_two_party: false,
        }
    }
}

# Validate cell inputs against the matrix SSOT under config/matrix/.
# Errors readably when scenario, browser, platform, or version is not in rules.
# When scenario has a receiver in the matrix rules, also validates receiver_platform/version.
# Returns the resolved flow_id for downstream use.
export def validate-cell-rules [
    scenario: string,
    sender_platform: string,
    sender_version: string,
    browser: string,
    receiver_platform: string = "",
    receiver_version: string = "",
] {
    let root = get-ocmts-root
    let rules = (load-matrix-rules $root)
    let known_scenarios = ($rules.scenarios | columns)
    if not ($scenario in $known_scenarios) {
        error make {msg: $"Scenario '($scenario)' not in config/matrix/. Known: ($known_scenarios | str join ', ')"}
    }
    let sc = ($rules.scenarios | get $scenario)

    # Resolve and validate flow_id.
    let flow_id = ($sc.flow_id? | default $scenario)
    validate-path-segment $flow_id "flow_id"
    if not ($flow_id in $PUBLIC_FLOW_IDS) {
        error make {msg: $"flow_id '($flow_id)' not in public flow id allowlist: ($PUBLIC_FLOW_IDS | str join ', ')"}
    }

    let known_browsers = $sc.browsers
    if not ($browser in $known_browsers) {
        error make {msg: $"Browser '($browser)' not valid for scenario '($scenario)'. Known: ($known_browsers | str join ', ')"}
    }
    let sender = $sc.sender
    if $sender.platform != $sender_platform {
        error make {msg: $"Sender platform '($sender_platform)' not valid for scenario '($scenario)'. Expected: ($sender.platform)"}
    }
    let known_sender_versions = $sender.version_lines
    if not ($sender_version in $known_sender_versions) {
        error make {msg: $"Sender version '($sender_version)' not in matrix for '($scenario)'/'($sender_platform)'. Known: ($known_sender_versions | str join ', ')"}
    }
    # Validate receiver when the scenario rules define a receiver.
    let sc_receiver = $sc.receiver?
    if $sc_receiver != null {
        if ($receiver_platform | is-empty) {
            error make {msg: $"Scenario '($scenario)' requires --receiver-platform (expected: ($sc_receiver.platform))"}
        }
        if ($receiver_version | is-empty) {
            error make {msg: $"Scenario '($scenario)' requires --receiver-version"}
        }
        if $receiver_platform != $sc_receiver.platform {
            error make {msg: $"Receiver platform '($receiver_platform)' not valid for scenario '($scenario)'. Expected: ($sc_receiver.platform)"}
        }
        let known_recv_versions = $sc_receiver.version_lines
        if not ($receiver_version in $known_recv_versions) {
            error make {msg: $"Receiver version '($receiver_version)' not in matrix for '($scenario)'/'($receiver_platform)'. Known: ($known_recv_versions | str join ', ')"}
        }
        # Enforce version pairing policy.
        let pairing = ($sc.version_pairing? | default "cross_product")
        match $pairing {
            "cross_product" => {}
            "explicit_pairs" => {
                let vp = ($sc.version_pairs? | default [])
                if ($vp | is-empty) {
                    error make {msg: $"Scenario '($scenario)' has explicit_pairs but empty version_pairs list"}
                }
                let pair_ok = ($vp | any {|p| ($p.sender == $sender_version) and ($p.receiver == $receiver_version)})
                if not $pair_ok {
                    error make {msg: $"Version pair sender=($sender_version)/receiver=($receiver_version) not in explicit_pairs for scenario '($scenario)'"}
                }
            }
            _ => {
                error make {msg: $"Scenario '($scenario)': unknown version_pairing '($pairing)'"}
            }
        }
    }

    $flow_id
}
