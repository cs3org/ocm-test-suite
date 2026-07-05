# Two-party IdP env emission: mirrored sender/receiver CYPRESS_*_idp_* and
# IdP hosts in NO_PROXY for external-idp platforms (cernbox).
# Run: nu scripts/tests/compose/idp-origin-two-party.nu

const SUITE_PATH = path self
const FIXTURE_EXEC_ID = "20260101t000000-aabbccdd"

use ../../lib/compose/topology-common.nu [party-idp-env]
use ../../lib/compose/topology-two-party.nu [write-two-party-env write-two-party-overlays]
use ../../lib/domain/core/ocmts-root.nu [get-ocmts-root]
use ../../lib/images/resolve.nu [resolve-images resolve-receiver-images]
use ../../lib/run/execution-id.nu [execution-temp-path]
use ../../lib/tests/assert.nu *
use ../../lib/tests/runner.nu [run-suite]

def read-stack-env-lines [env_file: string] {
    (open $env_file | lines | each {|l| ($l | str trim)} | where {|l| not ($l | is-empty)})
}

def read-text [path: string] {
    open -r $path
}

def link-path [src: string, dest: string] {
    mkdir ($dest | path dirname)
    ^ln -sf $src $dest
}

# Minimal config-root fixture: share-with matrix tuple cernbox/cernbox only.
def write-cernbox-two-party-fixture-root [real_root: string, fixture_root: string] {
    let cfg = ($fixture_root | path join "config")
    let matrix_flows = ($cfg | path join "matrix" "flows")
    let actors = ($cfg | path join "actors")
    mkdir $matrix_flows
    mkdir ($actors | path join "overrides")

    link-path ($real_root | path join "config" "compose" "cookbooks") ($cfg | path join "compose" "cookbooks")
    link-path ($real_root | path join "config" "images.nuon") ($cfg | path join "images.nuon")
    link-path ($real_root | path join "config" "matrix" "defaults.nuon") ($cfg | path join "matrix" "defaults.nuon")
    link-path ($real_root | path join "config" "matrix" "platforms.nuon") ($cfg | path join "matrix" "platforms.nuon")
    link-path ($real_root | path join "config" "matrix" "capabilities.v1.nuon") ($cfg | path join "matrix" "capabilities.v1.nuon")
    for flow in [login contact-wayf contact-token] {
        link-path ($real_root | path join "config" "matrix" "flows" $"($flow).nuon") ($matrix_flows | path join $"($flow).nuon")
    }
    link-path ($real_root | path join "config" "actors" "platforms") ($actors | path join "platforms")
    link-path ($real_root | path join "scripts") ($fixture_root | path join "scripts")

    let share_with = (open ($real_root | path join "config/matrix/flows/share-with.nuon"))
    let share_with_cernbox = (
        $share_with
        | upsert include (
            $share_with.include
            | append {sender: ["cernbox"], receiver: ["cernbox"], version_pairing: "cross_product"}
        )
        | upsert versions_sender ($share_with.versions_sender | upsert cernbox ["v11"])
        | upsert versions_receiver ($share_with.versions_receiver | upsert cernbox ["v11"])
    )
    $share_with_cernbox | to nuon | save --force ($matrix_flows | path join "share-with.nuon")

    let defaults = (open ($real_root | path join "config/actors/defaults.nuon"))
    let sw = ($defaults.flows.share-with)
    let sw_cernbox = (
        $sw
        | upsert sender (
            $sw.sender
            | upsert by_platform ($sw.sender.by_platform | upsert cernbox "einstein")
        )
        | upsert receiver (
            $sw.receiver
            | upsert by_platform ($sw.receiver.by_platform | upsert cernbox "einstein")
        )
    )
    ($defaults | upsert flows ($defaults.flows | upsert share-with $sw_cernbox))
    | to nuon
    | save --force ($actors | path join "defaults.nuon")
}

def cleanup-overlay-artifacts [artifacts_base: string, execution_id: string, fixture_root?: string] {
    rm -rf $artifacts_base
    rm -rf (execution-temp-path $execution_id)
    if $fixture_root != null {
        rm -rf $fixture_root
    }
}

def make-art-inputs [] {
    let base = ($nu.temp-dir | path join $"idp-origin-2p-test-(random uuid)")
    let art_inputs = ($base | path join "compose" "inputs")
    mkdir $art_inputs
    {base: $base, art_inputs: $art_inputs}
}

def test-cernbox-two-party-emits-mirrored-idp-env [] {
    test-log "\n[test-cernbox-two-party-emits-mirrored-idp-env]"
    let root = (get-ocmts-root)
    let dirs = (make-art-inputs)
    let sender_idp_env = (party-idp-env $root "cernbox" 1)
    let receiver_idp_env = (party-idp-env $root "cernbox" 2)
    let env_file = (
        write-two-party-env
            $dirs.art_inputs "cernbox" "cernbox" "v11" "v11"
            "ghcr.io/example/cernbox-web:sender" "ghcr.io/example/cernbox-web:receiver"
            "mariadb:11" "valkey:7" false $root null null "10.1.2.0/24"
            $sender_idp_env $receiver_idp_env {} {}
    )
    let lines = (read-stack-env-lines $env_file)
    let sender_no_proxy = (
        $lines
        | where {|l| $l | str starts-with "SENDER_NO_PROXY="}
        | first
        | str substring 16..
    )
    let receiver_no_proxy = (
        $lines
        | where {|l| $l | str starts-with "RECEIVER_NO_PROXY="}
        | first
        | str substring 18..
    )
    let results = [
        (assert-list-contains $lines "SENDER_IDP_HOST=idp1.docker"
            "stack.env has SENDER_IDP_HOST")
        (assert-list-contains $lines "SENDER_IDP_ORIGIN=https://idp1.docker"
            "stack.env has SENDER_IDP_ORIGIN")
        (assert-list-contains $lines "RECEIVER_IDP_HOST=idp2.docker"
            "stack.env has RECEIVER_IDP_HOST")
        (assert-list-contains $lines "RECEIVER_IDP_ORIGIN=https://idp2.docker"
            "stack.env has RECEIVER_IDP_ORIGIN")
        (assert-list-contains $lines "CYPRESS_sender_idp_origin=https://idp1.docker"
            "stack.env has CYPRESS_sender_idp_origin")
        (assert-list-contains $lines "CYPRESS_receiver_idp_origin=https://idp2.docker"
            "stack.env has CYPRESS_receiver_idp_origin")
        (assert-list-contains $lines "CYPRESS_sender_idp_realm=cernbox"
            "stack.env has CYPRESS_sender_idp_realm")
        (assert-list-contains $lines "CYPRESS_receiver_idp_realm=cernbox"
            "stack.env has CYPRESS_receiver_idp_realm")
        (assert-string-contains $sender_no_proxy "idp1.docker"
            "SENDER_NO_PROXY bypasses sender IdP host")
        (assert-string-contains $receiver_no_proxy "idp2.docker"
            "RECEIVER_NO_PROXY bypasses receiver IdP host")
    ]
    rm -rf $dirs.base
    $results
}

def test-cernbox-two-party-overlays-idp-passthrough [] {
    test-log "\n[test-cernbox-two-party-overlays-idp-passthrough]"
    let real_root = (get-ocmts-root)
    let fixture_root = ($nu.temp-dir | path join $"idp-2p-fixture-(random uuid)")
    write-cernbox-two-party-fixture-root $real_root $fixture_root
    let artifacts_base = ($nu.temp-dir | path join $"idp-2p-overlay-(random uuid)")
    mkdir ($artifacts_base | path join "compose" "inputs")
    let sender_imgs = (
        with-env {OCMTS_ROOT: $fixture_root} {
            resolve-images "cernbox" "v11" --matrix-key "share-with__cernbox__cernbox" --flow-id "share-with"
        }
    )
    let recv_imgs = (
        with-env {OCMTS_ROOT: $fixture_root} {
            resolve-receiver-images "cernbox" "v11" --matrix-key "share-with__cernbox__cernbox" --flow-id "share-with"
        }
    )
    let overlay = (
        with-env {OCMTS_ROOT: $fixture_root} {
            write-two-party-overlays "share-with" "cernbox" "cernbox" "cell-share-cernbox-v11" $FIXTURE_EXEC_ID $sender_imgs.platform $recv_imgs.platform "mitmproxy:test" "cypress:ci" "cypress:dev" "mariadb:11" "valkey:7" "cypress/e2e/share-with/index.cy.ts" "chrome" false $fixture_root $artifacts_base "v11" "v11" $sender_imgs.bundle $recv_imgs.bundle
        }
    )
    let lines = (read-stack-env-lines $overlay.env_file)
    let runner_ci = (read-text ($overlay.compose_d | path join "runner-ci.yml"))
    let runner_dev = (read-text ($overlay.compose_d | path join "runner-dev.yml"))
    let results = [
        (assert-list-contains $lines "SENDER_IDP_ORIGIN=https://idp1.docker"
            "overlay stack.env has SENDER_IDP_ORIGIN")
        (assert-list-contains $lines "RECEIVER_IDP_ORIGIN=https://idp2.docker"
            "overlay stack.env has RECEIVER_IDP_ORIGIN")
        (assert-list-contains $lines "CYPRESS_sender_idp_origin=https://idp1.docker"
            "overlay stack.env has CYPRESS_sender_idp_origin")
        (assert-list-contains $lines "CYPRESS_receiver_idp_origin=https://idp2.docker"
            "overlay stack.env has CYPRESS_receiver_idp_origin")
        (assert-string-contains $runner_ci "CYPRESS_sender_idp_origin=https://idp1.docker"
            "runner-ci.yml passthrough CYPRESS_sender_idp_origin")
        (assert-string-contains $runner_ci "CYPRESS_sender_idp_realm=cernbox"
            "runner-ci.yml passthrough CYPRESS_sender_idp_realm")
        (assert-string-contains $runner_ci "CYPRESS_receiver_idp_origin=https://idp2.docker"
            "runner-ci.yml passthrough CYPRESS_receiver_idp_origin")
        (assert-string-contains $runner_ci "CYPRESS_receiver_idp_realm=cernbox"
            "runner-ci.yml passthrough CYPRESS_receiver_idp_realm")
        (assert-string-contains $runner_dev "CYPRESS_sender_idp_origin=https://idp1.docker"
            "runner-dev.yml passthrough CYPRESS_sender_idp_origin")
        (assert-string-contains $runner_dev "CYPRESS_sender_idp_realm=cernbox"
            "runner-dev.yml passthrough CYPRESS_sender_idp_realm")
        (assert-string-contains $runner_dev "CYPRESS_receiver_idp_origin=https://idp2.docker"
            "runner-dev.yml passthrough CYPRESS_receiver_idp_origin")
        (assert-string-contains $runner_dev "CYPRESS_receiver_idp_realm=cernbox"
            "runner-dev.yml passthrough CYPRESS_receiver_idp_realm")
    ]
    cleanup-overlay-artifacts $artifacts_base $FIXTURE_EXEC_ID $fixture_root
    $results
}

def main [] {
    test-log "=== compose/idp-origin-two-party Tests ==="
    let results = (
        (test-cernbox-two-party-emits-mirrored-idp-env)
        | append (test-cernbox-two-party-overlays-idp-passthrough)
    ) | flatten
    run-suite "compose/idp-origin-two-party" $SUITE_PATH $results
}
