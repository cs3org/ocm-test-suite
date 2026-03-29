# Compute deterministic cell and artifact identifiers.

use ./execution-id.nu [validate-path-segment]
use ./domain/core/ocmts-root.nu [get-ocmts-root]

# Validate browser against the supported allowlist for the current image slice.
# Only chrome is supported in the current images. Error message is readable.
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
export def compute-cell [
    scenario: string,
    sender_platform: string,
    sender_version: string,
    browser: string,
    receiver_platform: string = "",
    receiver_version: string = "",
] {
    let s = (validate-path-segment $scenario "scenario")
    let p = (validate-path-segment $sender_platform "sender_platform")
    let v = (validate-path-segment $sender_version "sender_version")
    let b = (validate-browser $browser)
    let is_two_party = (not ($receiver_platform | is-empty))
    if $is_two_party {
        let rp = (validate-path-segment $receiver_platform "receiver_platform")
        let rv = (validate-path-segment $receiver_version "receiver_version")
        {
            cell_id: $"($s)__($p)-($v)__($rp)-($rv)",
            artifact_name: $"cell-($s)-($p)-($v)-($rp)-($rv)",
            scenario: $s,
            sender_platform: $p,
            sender_version: $v,
            receiver_platform: $rp,
            receiver_version: $rv,
            browser: $b,
            is_two_party: true,
        }
    } else {
        {
            cell_id: $"($s)__($p)-($v)",
            artifact_name: $"cell-($s)-($p)-($v)",
            scenario: $s,
            sender_platform: $p,
            sender_version: $v,
            receiver_platform: "",
            receiver_version: "",
            browser: $b,
            is_two_party: false,
        }
    }
}

# Validate cell inputs against config/matrix-rules.nuon.
# Errors readably when scenario, browser, platform, or version is not in rules.
# When scenario has a receiver in the matrix rules, also validates receiver_platform/version.
export def validate-cell-rules [
    scenario: string,
    sender_platform: string,
    sender_version: string,
    browser: string,
    receiver_platform: string = "",
    receiver_version: string = "",
] {
    let root = get-ocmts-root
    let rules = open ($root | path join "config/matrix-rules.nuon")
    let known_scenarios = ($rules.scenarios | columns)
    if not ($scenario in $known_scenarios) {
        error make {msg: $"Scenario '($scenario)' not in config/matrix-rules.nuon. Known: ($known_scenarios | str join ', ')"}
    }
    let sc = ($rules.scenarios | get $scenario)
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
    }
}
