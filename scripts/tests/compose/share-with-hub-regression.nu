# share-with flow regression: unchanged topology must not gain sender-hub wiring.
# Run: nu scripts/tests/compose/share-with-hub-regression.nu

const SUITE_PATH = path self

use ../../lib/compose/topology-two-party.nu [write-two-party-overlays]
use ../../lib/domain/core/ocmts-root.nu [get-ocmts-root]
use ../../lib/images/resolve.nu [resolve-images resolve-receiver-images]
use ../../lib/tests/assert.nu *
use ../../lib/tests/runner.nu [run-suite]
use ./_webapp-share-overlay-fixtures.nu [
    FIXTURE_EXEC_ID
    read-stack-env-lines
    read-text
    extract-compose-service-block
    cleanup-overlay-artifacts
]

def test-share-with-unchanged-no-sender-hub [] {
    test-log "\n[test-share-with-unchanged-no-sender-hub]"
    let root = (get-ocmts-root)
    let artifacts_base = ($nu.temp-dir | path join $"share-with-regression-(random uuid)")
    mkdir ($artifacts_base | path join "compose" "inputs")
    let sender_imgs = (
        resolve-images "nextcloud" "v32"
            --matrix-key "share-with__nextcloud__nextcloud" --flow-id "share-with"
    )
    let recv_imgs = (
        resolve-receiver-images "nextcloud" "v32"
            --matrix-key "share-with__nextcloud__nextcloud" --flow-id "share-with"
    )
    let overlay = (write-two-party-overlays
        "share-with" "nextcloud" "nextcloud" "cell-share-nc-v32" $FIXTURE_EXEC_ID
        $sender_imgs.platform $recv_imgs.platform "mitmproxy:test"
        $sender_imgs.cypress_ci $sender_imgs.cypress_dev
        $sender_imgs.mariadb $sender_imgs.valkey
        "cypress/e2e/share-with/index.cy.ts" "chrome" false
        $root $artifacts_base
        "v32" "v32"
    )
    let lines = (read-stack-env-lines $overlay.env_file)
    let sender_yml = (read-text ($overlay.compose_d | path join "sender.yml"))
    let sender_block = (extract-compose-service-block $sender_yml "sender")
    let runner_ci = (read-text ($overlay.compose_d | path join "runner-ci.yml"))
    let hub_overlay = ($overlay.compose_d | path join "webapp-hub.yml")
    let results = [
        (assert-truthy (not ($hub_overlay | path exists))
            "share-with does not copy webapp-hub overlay")
        (assert-truthy (not ($overlay.base_overlay_fnames | any {|f| $f == "webapp-hub.yml"}))
            "share-with base_overlay_fnames omits webapp-hub.yml")
        (assert-not-null $sender_block "share-with sender service block exists")
        (assert-truthy (not ($sender_block | str contains "JUPYTER_HOST"))
            "share-with sender overlay omits JUPYTER_HOST")
        (assert-truthy (not ($sender_block | str contains "SENDER_HUB_HOST"))
            "share-with sender overlay omits SENDER_HUB_HOST substitution")
        (assert-truthy (not ($sender_block | str contains "oauth-handoff"))
            "share-with sender overlay omits the oauth-handoff wiring")
        (assert-truthy (not (($artifacts_base | path join "oauth-handoff") | path exists))
            "share-with does not create the oauth-handoff shared dir")
        (assert-truthy (
            $lines | where {|l| $l | str starts-with "SENDER_HUB_HOST="} | is-empty
        ) "share-with stack.env omits SENDER_HUB_HOST")
        (assert-truthy (
            $lines | where {|l| $l | str starts-with "SENDER_HUB_IMAGE="} | is-empty
        ) "share-with stack.env omits SENDER_HUB_IMAGE")
        (assert-list-contains $lines "SENDER_TRUSTED_DOMAINS=nextcloud1.docker"
            "share-with stack.env sets default sender trusted domains without hub host")
        (assert-truthy (not ($runner_ci | str contains "sender-hub:"))
            "share-with runner does not depend on sender-hub")
    ]
    cleanup-overlay-artifacts $artifacts_base $FIXTURE_EXEC_ID
    $results
}

def main [] {
    test-log "=== compose/share-with-hub-regression Tests ==="
    let results = (test-share-with-unchanged-no-sender-hub) | flatten
    run-suite "compose/share-with-hub-regression" $SUITE_PATH $results
}
