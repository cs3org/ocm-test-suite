# Compute deterministic cell and artifact identifiers.

use ../run/execution-id.nu [validate-path-segment validate-matrix-key]
use ../domain/core/ocmts-root.nu [get-ocmts-root]
use ../run/flow-ids.nu [PUBLIC_FLOW_IDS]
use ./topology.nu [
    require-receiver-platform-for-two-party
    reject-spurious-receiver-version-for-one-party
]
use ./rules-gen.nu [expand-flow load-matrix-rules matrix-key]

# Validate tuple identity segments before matrix lookup or filesystem paths.
# Returns sanitized flow_id, sender_platform, receiver_platform, and matrix_key.
export def tuple-matrix-key [
    flow_id: string,
    sender_platform: string,
    receiver_platform: string = "",
] {
    let fid = (validate-path-segment $flow_id "flow_id")
    let sp = (validate-path-segment $sender_platform "sender_platform")
    let rp = if ($receiver_platform | is-empty) {
        ""
    } else {
        (validate-path-segment $receiver_platform "receiver_platform")
    }
    let mk = if ($rp | is-empty) {
        (matrix-key $fid $sp "")
    } else {
        (matrix-key $fid $sp $rp)
    }
    validate-matrix-key $mk
    {
        flow_id: $fid,
        sender_platform: $sp,
        receiver_platform: $rp,
        matrix_key: $mk,
    }
}

# nuon may store a lone explicit_pairs entry as a record instead of a one-item list.
def as-version-pair-list [raw: any] {
    if $raw == null {
        return []
    }
    if ($raw | describe | str starts-with "list") {
        return $raw
    }
    if ($raw | is-empty) {
        return []
    }
    [$raw]
}

export def matrix-entry-state [root: string, flow_id: string, matrix_key: string] {
    let rules = (load-matrix-rules $root)
    let known = ($rules.matrix | columns)
    let entry = ($rules.matrix | get --optional $matrix_key)
    if $entry != null {
        if ($entry.enabled? | default false) {
            return {
                state: "enabled"
                known: $known
            }
        }
        return {
            state: "disabled"
            known: $known
        }
    }

    let flow_path = ($root | path join $"config/matrix/flows/($flow_id).nuon")
    if not ($flow_path | path exists) {
        return {
            state: "absent"
            known: $known
        }
    }

    let flow = (open $flow_path)
    if ($flow.enabled? | default false) {
        return {
            state: "absent"
            known: $known
        }
    }

    let defaults = (open ($root | path join "config/matrix/defaults.nuon"))
    let platforms_data = (open ($root | path join "config/matrix/platforms.nuon"))
    let disabled_keys = (
        expand-flow
            ($flow | upsert enabled true)
            $platforms_data.platforms
            $defaults.browsers_default
        | get key
    )

    if $matrix_key in $disabled_keys {
        return {
            state: "disabled"
            known: ($known | append $disabled_keys | uniq | sort)
        }
    }

    {
        state: "absent"
        known: ($known | append $disabled_keys | uniq | sort)
    }
}

# Error if the matrix entry for this tuple is not enabled.
# Call from run entrypoints to reject placeholder cells early.
export def assert-matrix-entry-enabled [
    flow_id: string,
    sender_platform: string,
    receiver_platform: string = "",
] {
    let root = get-ocmts-root
    let fid = (validate-path-segment $flow_id "flow_id")
    let canonical_two_party = (
        require-receiver-platform-for-two-party $fid $receiver_platform
    )
    let tuple = (tuple-matrix-key $fid $sender_platform $receiver_platform)
    let mk = $tuple.matrix_key
    let state = (matrix-entry-state $root $tuple.flow_id $mk)
    match $state.state {
        "enabled" => {}
        "disabled" => {
            error make {
                msg: $"Matrix entry '($mk)' is disabled \(enabled: false\). Placeholder cells cannot be run."
            }
        }
        _ => {
            error make {
                msg: $"Matrix entry '($mk)' not in config/matrix/. Known: ($state.known | str join ', ')"
            }
        }
    }
}

# Validate browser token shape. Matrix entry allowlist is enforced in validate-cell-rules.
export def validate-browser [browser: string] {
    validate-path-segment $browser "browser"
    $browser
}

# Compute cell_id and artifact_name for one-party or two-party tuples.
# cell_id shape is unchanged: <flow_id>__<sender>-<sver>[__<recv>-<rver>]
export def compute-cell [
    flow_id: string,
    sender_platform: string,
    sender_version: string,
    browser: string,
    receiver_platform: string = "",
    receiver_version: string = "",
] {
    let fid = (validate-path-segment $flow_id "flow_id")
    let is_two_party = (
        require-receiver-platform-for-two-party $fid $receiver_platform
    )
    reject-spurious-receiver-version-for-one-party $fid $receiver_version
    let tuple = (tuple-matrix-key $fid $sender_platform $receiver_platform)
    let mk = $tuple.matrix_key
    let p = $tuple.sender_platform
    let v = (validate-path-segment $sender_version "sender_version")
    let b = (validate-browser $browser)
    if $is_two_party {
        if ($receiver_version | is-empty) {
            error make {
                msg: $"Flow '($fid)' requires --receiver-version for two-party flows"
            }
        }
        let rp = $tuple.receiver_platform
        let rv = (validate-path-segment $receiver_version "receiver_version")
        {
            flow_id: $fid,
            matrix_key: $mk,
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
            matrix_key: $mk,
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
# Resolves the tuple to a matrix_key and validates platforms, versions, and browser.
export def validate-cell-rules [
    flow_id: string,
    sender_platform: string,
    sender_version: string,
    browser: string,
    receiver_platform: string = "",
    receiver_version: string = "",
] {
    let root = get-ocmts-root
    let fid = (validate-path-segment $flow_id "flow_id")
    let canonical_two_party = (
        require-receiver-platform-for-two-party $fid $receiver_platform
    )
    reject-spurious-receiver-version-for-one-party $fid $receiver_version
    if $canonical_two_party and ($receiver_version | is-empty) {
        error make {
            msg: $"Flow '($fid)' requires --receiver-version for two-party flows"
        }
    }
    let tuple = (tuple-matrix-key $fid $sender_platform $receiver_platform)
    let mk = $tuple.matrix_key
    let rules = (load-matrix-rules $root)
    let state = (matrix-entry-state $root $tuple.flow_id $mk)
    match $state.state {
        "enabled" => {}
        "disabled" => {
            error make {
                msg: $"Matrix entry '($mk)' is disabled \(enabled: false\). Placeholder cells cannot be run."
            }
        }
        _ => {
            error make {msg: $"Matrix entry '($mk)' not in config/matrix/. Known: ($state.known | str join ', ')"}
        }
    }
    let entry = ($rules.matrix | get $mk)

    let eff_flow_id = ($entry.flow_id? | default $flow_id)
    validate-path-segment $eff_flow_id "flow_id"
    if not ($eff_flow_id in $PUBLIC_FLOW_IDS) {
        error make {msg: $"flow_id '($eff_flow_id)' not in public flow id allowlist: ($PUBLIC_FLOW_IDS | str join ', ')"}
    }

    let known_browsers = $entry.browsers
    if not ($browser in $known_browsers) {
        error make {msg: $"Browser '($browser)' not valid for matrix entry '($mk)'. Known: ($known_browsers | str join ', ')"}
    }
    let sender = $entry.sender
    if $sender.platform != $sender_platform {
        error make {msg: $"Sender platform '($sender_platform)' not valid for matrix entry '($mk)'. Expected: ($sender.platform)"}
    }
    let known_sender_versions = $sender.version_lines
    if not ($sender_version in $known_sender_versions) {
        error make {msg: $"Sender version '($sender_version)' not in matrix for '($mk)'/'($sender_platform)'. Known: ($known_sender_versions | str join ', ')"}
    }
    let entry_receiver = $entry.receiver?
    if $entry_receiver != null {
        if ($receiver_platform | is-empty) {
            error make {msg: $"Matrix entry '($mk)' requires --receiver-platform \(expected: ($entry_receiver.platform)\)"}
        }
        if ($receiver_version | is-empty) {
            error make {msg: $"Matrix entry '($mk)' requires --receiver-version"}
        }
        if $receiver_platform != $entry_receiver.platform {
            error make {msg: $"Receiver platform '($receiver_platform)' not valid for matrix entry '($mk)'. Expected: ($entry_receiver.platform)"}
        }
        let known_recv_versions = $entry_receiver.version_lines
        if not ($receiver_version in $known_recv_versions) {
            error make {msg: $"Receiver version '($receiver_version)' not in matrix for '($mk)'/'($receiver_platform)'. Known: ($known_recv_versions | str join ', ')"}
        }
        let pairing = ($entry.version_pairing? | default "cross_product")
        match $pairing {
            "cross_product" => {}
            "explicit_pairs" => {
                let vp = (as-version-pair-list ($entry.version_pairs? | default []))
                if ($vp | is-empty) {
                    error make {msg: $"Matrix entry '($mk)' has explicit_pairs but empty version_pairs list"}
                }
                let pair_ok = ($vp | any {|p| ($p.sender == $sender_version) and ($p.receiver == $receiver_version)})
                if not $pair_ok {
                    error make {msg: $"Version pair sender=($sender_version)/receiver=($receiver_version) not in explicit_pairs for matrix entry '($mk)'"}
                }
            }
            _ => {
                error make {msg: $"Matrix entry '($mk)': unknown version_pairing '($pairing)'"}
            }
        }
    }

    $eff_flow_id
}
