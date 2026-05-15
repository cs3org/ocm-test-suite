# Actor config validator.
# Derives topology from the matrix SSOT rather than override file shape.
# Validates all actor credentials for enabled scenarios.

use ../matrix/topology.nu [flow-is-two-party]
use ../matrix/rules-gen.nu [load-matrix-rules]
use ./load.nu [load-actor-for-scenario load-sender-for-scenario load-receiver-for-scenario]

# Validate actor config for a scenario; errors readably when anything is wrong.
# Topology (one-party vs two-party) is derived from the matrix SSOT, not the
# override file's shape. When sender_platform is non-empty, passes it into the
# loader for inference and mismatch checks. When receiver_platform is non-empty
# (two-party only), passes it into the loader similarly.
export def validate-actor-config [
    scenario: string,
    root: string,
    sender_platform: string = "",
    receiver_platform: string = "",
    --flow-id: string = "",
] {
    # Determine canonical topology from matrix flow_id (matrix is SSOT for
    # topology, not the override file's shape).
    let topology = if not ($flow_id | is-empty) {
        {fid: $flow_id, two_party: (flow-is-two-party $flow_id)}
    } else {
        let rules = (load-matrix-rules $root)
        let entry = ($rules.scenarios | get --optional $scenario)
        if $entry == null {
            error make {msg: $"Scenario '($scenario)' not found in matrix SSOT and no --flow-id provided; cannot determine topology"}
        }
        let fid = ($entry.flow_id? | default "")
        if $fid == "" {
            error make {msg: $"Matrix entry for '($scenario)' has no flow_id"}
        }
        {fid: $fid, two_party: (flow-is-two-party $fid)}
    }
    let canonical_two_party = $topology.two_party
    let fid_used = $topology.fid

    # When override file is present and has real content, check that its
    # shape agrees with the canonical topology from the matrix.
    let cfg_path = ($root | path join $"config/actors/scenarios/($scenario).nuon")
    if ($cfg_path | path exists) {
        let cfg = (open $cfg_path)
        let file_two_party = (
            (($cfg.sender? | default {} | is-empty) == false)
            or (($cfg.receiver? | default {} | is-empty) == false)
        )
        let file_one_party = (($cfg.actor? | default {} | is-empty) == false)
        let file_has_real = ($file_two_party or $file_one_party)
        if $file_has_real and ($file_two_party != $canonical_two_party) {
            error make {msg: $"Override file shape for scenario '($scenario)' \(flow '($fid_used)'\) implies two_party=($file_two_party) but matrix says two_party=($canonical_two_party). Fix the override file or matrix."}
        }
    }

    if $canonical_two_party {
        let sender = (load-sender-for-scenario $scenario $root $sender_platform)
        if $sender == null {
            error make {msg: $"Sender actor config not found for scenario '($scenario)'"}
        }
        let receiver = (load-receiver-for-scenario $scenario $root $receiver_platform)
        if $receiver == null {
            error make {msg: $"Receiver actor config not found for scenario '($scenario)'"}
        }
    } else {
        load-actor-for-scenario $scenario $root $sender_platform
    }
}
