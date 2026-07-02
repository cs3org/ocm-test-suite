# Actor config validator.
# Derives topology from the matrix SSOT rather than override file shape.

use ../matrix/topology.nu [require-receiver-platform-for-two-party]
use ../matrix/cell.nu [matrix-entry-state tuple-matrix-key]
use ../matrix/rules-gen.nu [load-matrix-rules]
use ../run/execution-id.nu [validate-path-segment]
use ./load.nu [
    load-actor-for-tuple
    load-sender-for-tuple
    load-receiver-for-tuple
    assert-file-has-real-overrides
    role-block-has-real-values
]

export def require-sender-platform [sender_platform: any] {
    let sp = ($sender_platform | default "")
    if ($sp | is-empty) {
        error make {
            msg: "--sender-platform is required for tuple-based actor lookup"
        }
    }
    $sp
}

export def validate-actor-config [
    flow_id: string,
    root: string,
    sender_platform: string = "",
    receiver_platform: string = "",
] {
    let sender_platform = (require-sender-platform $sender_platform)
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
                msg: ([
                    $"Matrix entry '($mk)' is disabled "
                    "(enabled: false). Placeholder cells cannot be run."
                ] | str join "")
            }
        }
        _ => {
            error make {
                msg: $"Matrix entry '($mk)' not in config/matrix/. Known: ($state.known | str join ', ')"
            }
        }
    }
    let rules = (load-matrix-rules $root)
    let entry = ($rules.matrix | get $mk)
    let eff_fid = ($entry.flow_id? | default $tuple.flow_id)
    if $eff_fid == "" {
        error make {msg: $"Matrix entry '($mk)' has no flow_id"}
    }

    let cfg_path = ($root | path join $"config/actors/overrides/($mk).nuon")
    let cfg_rel_path = $"config/actors/overrides/($mk).nuon"
    if ($cfg_path | path exists) {
        let cfg = (open $cfg_path)
        assert-file-has-real-overrides $cfg $cfg_rel_path
        let file_two_party = (
            (
                if ($cfg.sender? | default null) == null { false }
                else { role-block-has-real-values ($cfg.sender) }
            )
            or (
                if ($cfg.receiver? | default null) == null { false }
                else { role-block-has-real-values ($cfg.receiver) }
            )
        )
        let file_one_party = (
            if ($cfg.actor? | default null) == null { false }
            else { role-block-has-real-values ($cfg.actor) }
        )
        if ($file_two_party or $file_one_party) and ($file_two_party != $canonical_two_party) {
            error make {msg: $"Override file shape for matrix entry '($mk)' \(flow '($eff_fid)'\) implies two_party=($file_two_party) but matrix says two_party=($canonical_two_party). Fix the override file or matrix."}
        }
    }

    if $canonical_two_party {
        let sender = (load-sender-for-tuple $tuple.flow_id $tuple.sender_platform $tuple.receiver_platform $root $tuple.sender_platform)
        if $sender == null {
            error make {msg: $"Sender actor config not found for matrix entry '($mk)'"}
        }
        let receiver = (load-receiver-for-tuple $tuple.flow_id $tuple.sender_platform $tuple.receiver_platform $root $tuple.receiver_platform)
        if $receiver == null {
            error make {msg: $"Receiver actor config not found for matrix entry '($mk)'"}
        }
    } else {
        load-actor-for-tuple $tuple.flow_id $tuple.sender_platform $root $tuple.sender_platform
    }
}
