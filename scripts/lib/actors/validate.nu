# Actor config validator.
# Detects one-party vs two-party topology and validates all actor credentials.

use ../matrix/topology.nu [flow-is-two-party]
use ./load.nu [load-actor-for-scenario load-sender-for-scenario load-receiver-for-scenario]

# Validate actor config for a scenario; errors readably when anything is wrong.
# Detects one-party (actor field) vs two-party (sender/receiver fields) automatically.
# When sender_platform is non-empty, passes it into loader for inference and mismatch check.
# When receiver_platform is non-empty (two-party only), passes it into loader similarly.
export def validate-actor-config [
    scenario: string,
    root: string,
    sender_platform: string = "",
    receiver_platform: string = "",
    --flow-id: string = "",
] {
    let cfg_path = ($root | path join $"config/actors/scenarios/($scenario).nuon")
    if not ($cfg_path | path exists) {
        error make {msg: $"No actor config for scenario '($scenario)': config/actors/scenarios/($scenario).nuon not found"}
    }
    let cfg = (open $cfg_path)
    let is_two_party = (($cfg.sender? != null) and ($cfg.actor? == null))
    if not ($flow_id | is-empty) {
        let canonical = (flow-is-two-party $flow_id)
        if $is_two_party != $canonical {
            error make {msg: $"Topology mismatch for scenario '($scenario)' \(flow '($flow_id)'\): flow file declares two_party=($canonical) but actor config shape implies two_party=($is_two_party). Fix the actor config or the flow file."}
        }
    }

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
