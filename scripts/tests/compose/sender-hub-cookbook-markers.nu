# Guard B: committed nextcloud.sender.yml must contain sender-hub patch markers.
# Run: nu scripts/tests/compose/sender-hub-cookbook-markers.nu

const SUITE_PATH = path self

use ../../lib/compose/topology-sender-hub.nu [
    SENDER_HUB_NO_PROXY_MARKER
    SENDER_HUB_VOLUMES_MARKER
]
use ../../lib/domain/core/ocmts-root.nu [get-ocmts-root]
use ../../lib/tests/assert.nu *
use ../../lib/tests/runner.nu [run-suite]

def test-nextcloud-sender-cookbook-has-sender-hub-markers [] {
    test-log "\n[test-nextcloud-sender-cookbook-has-sender-hub-markers]"
    let root = (get-ocmts-root)
    let sender_yml = (
        open --raw ($root | path join "config/compose/cookbooks/nextcloud.sender.yml")
    )
    [
        (assert-string-contains $sender_yml $SENDER_HUB_NO_PROXY_MARKER
            "nextcloud.sender.yml contains SENDER_HUB_NO_PROXY_MARKER value")
        (assert-string-contains $sender_yml $SENDER_HUB_VOLUMES_MARKER
            "nextcloud.sender.yml contains SENDER_HUB_VOLUMES_MARKER value")
    ]
}

def main [] {
    test-log "=== compose/sender-hub-cookbook-markers Tests ==="
    let results = (test-nextcloud-sender-cookbook-has-sender-hub-markers) | flatten
    run-suite "compose/sender-hub-cookbook-markers" $SUITE_PATH $results
}
