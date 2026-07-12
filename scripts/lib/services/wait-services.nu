# Platform-up compose wait targets (service names after `up -d --wait`).

use ../run/flow-topology.nu [flow-has-sender-hub load-flow-topology]

export const TWO_PARTY_DEFAULT_WAIT_SERVICES = ["sender" "receiver" "mitm"]
export const SENDER_HUB_WAIT_SERVICE = "sender-hub"

# One-party: []. Two-party default: sender/receiver/mitm. Sender-hub flows append sender-hub.
export def platform-up-wait-services [
    is_two_party: bool,
    flow_id: string,
    root: string,
]: nothing -> list<string> {
    if not $is_two_party {
        return []
    }
    let topology = (load-flow-topology $root)
    if (flow-has-sender-hub $flow_id $topology) {
        $TWO_PARTY_DEFAULT_WAIT_SERVICES | append $SENDER_HUB_WAIT_SERVICE
    } else {
        $TWO_PARTY_DEFAULT_WAIT_SERVICES
    }
}
