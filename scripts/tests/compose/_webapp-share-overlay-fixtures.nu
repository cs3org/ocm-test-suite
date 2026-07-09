# Shared webapp-share overlay fixtures for compose test suites.
# Support module only: no `main`; imported by compose/webapp-share-*.nu and share-with-hub-regression.nu.

export const FIXTURE_EXEC_ID = "20260101t000000-aabbcc01"

use ../../lib/compose/topology-two-party.nu [write-two-party-overlays]
use ../../lib/images/resolve.nu [resolve-images resolve-receiver-images]
use ../../lib/run/execution-id.nu [execution-temp-path]
use ../../lib/run/flow-ids.nu [WEBAPP_SHARE_FLOW_ID]

export def read-stack-env-lines [env_file: string] {
    (open $env_file | lines | each {|l| ($l | str trim)} | where {|l| not ($l | is-empty)})
}

export def read-text [path: string] {
    open -r $path
}

def is-compose-top-level-service-line [line: string] {
    not (($line | parse --regex '^  [^\s].+:$' | is-empty))
}

export def extract-compose-service-block [src: string, service: string] {
    let marker = $"  ($service):"
    let lines = ($src | lines)
    let start = ($lines | enumerate | where {|e| $e.item == $marker} | first)
    if ($start == null) {
        return null
    }
    let tail = ($lines | skip ($start.index + 1))
    let next = ($tail | enumerate | where {|e| (is-compose-top-level-service-line $e.item)} | first)
    let end = if ($next == null) { ($tail | length) } else { $next.index }
    $tail | take $end | str join (char newline)
}

export def cleanup-overlay-artifacts [artifacts_base: string, execution_id: string] {
    rm -rf $artifacts_base
    rm -rf (execution-temp-path $execution_id)
}

export def make-webapp-share-overlay [
    root: string,
    artifacts_base: string,
    --receiver-platform: string = "cernbox",
    --receiver-version: string = "v11",
    --artifact-name: string = "cell-webapp-share-nc-v35",
] {
    let matrix_key = $"($WEBAPP_SHARE_FLOW_ID)__nextcloud__($receiver_platform)"
    let sender_imgs = (
        resolve-images "nextcloud" "v35"
            --matrix-key $matrix_key --flow-id $WEBAPP_SHARE_FLOW_ID
    )
    let recv_imgs = (
        resolve-receiver-images $receiver_platform $receiver_version
            --matrix-key $matrix_key --flow-id $WEBAPP_SHARE_FLOW_ID
    )
    (write-two-party-overlays
        $WEBAPP_SHARE_FLOW_ID "nextcloud" $receiver_platform $artifact_name $FIXTURE_EXEC_ID
        $sender_imgs.platform $recv_imgs.platform "mitmproxy:test"
        $sender_imgs.cypress_ci $sender_imgs.cypress_dev
        $sender_imgs.mariadb $sender_imgs.valkey
        "cypress/e2e/webapp-share/index.cy.ts" "chrome" false
        $root $artifacts_base
        "v35" $receiver_version
    )
}
