# Platform-up compose wait targets (service names after `up -d --wait`).

use ../run/flow-ids.nu [is-webapp-share-flow]

export const TWO_PARTY_DEFAULT_WAIT_SERVICES = ["sender" "receiver" "mitm"]
export const WEBAPP_SHARE_HUB_WAIT_SERVICE = "sender-hub"

# One-party: []. Two-party default: sender/receiver/mitm. webapp-share appends sender-hub.
export def platform-up-wait-services [
    is_two_party: bool,
    flow_id: string = "",
]: nothing -> list<string> {
    if not $is_two_party {
        return []
    }
    if (is-webapp-share-flow $flow_id) {
        $TWO_PARTY_DEFAULT_WAIT_SERVICES | append $WEBAPP_SHARE_HUB_WAIT_SERVICE
    } else {
        $TWO_PARTY_DEFAULT_WAIT_SERVICES
    }
}
