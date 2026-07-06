# Two-party bundle wiring: mirrored SENDER_/RECEIVER_*_IMAGE env lines and
# resolve-receiver-images bundle reduction for cernbox.
# Run: nu scripts/tests/compose/bundle-two-party.nu

const SUITE_PATH = path self

use ../../lib/compose/render.nu [write-compose-overlays]
use ../../lib/compose/topology-two-party.nu [write-two-party-env write-two-party-overlays]
use ../../lib/domain/core/ocmts-root.nu [get-ocmts-root]
use ../../lib/images/resolve.nu [resolve-images resolve-receiver-images]
use ../../lib/run/execution-id.nu [execution-temp-path]
use ../../lib/services/context.nu [setup-run-context]
use ../../lib/tests/assert.nu *
use ../../lib/tests/runner.nu [run-suite]

const FIXTURE_EXEC_ID = "20260101t000000-eeff0011"
const CERNBOX_SENDER_COOKBOOK = "config/compose/cookbooks/cernbox.sender.yml"
const CERNBOX_RECEIVER_COOKBOOK = "config/compose/cookbooks/cernbox.receiver.yml"

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
    let base = ($nu.temp-dir | path join $"bundle-2p-test-(random uuid)")
    let art_inputs = ($base | path join "compose" "inputs")
    mkdir $art_inputs
    {base: $base, art_inputs: $art_inputs}
}

def test-write-two-party-env-bundle-lines [] {
    test-log "\n[test-write-two-party-env-bundle-lines]"
    let root = (get-ocmts-root)
    let dirs = (make-art-inputs)
    let sender_bundle = {
        revad: "ghcr.io/example/cernbox-revad:sender",
        idp: "ghcr.io/example/idp:sender",
    }
    let receiver_bundle = {
        revad: "ghcr.io/example/cernbox-revad:receiver",
        idp: "ghcr.io/example/idp:receiver",
    }
    let env_file = (
        write-two-party-env
            $dirs.art_inputs "cernbox" "cernbox" "v11" "v11"
            "ghcr.io/example/cernbox-web:sender" "ghcr.io/example/cernbox-web:receiver"
            "mariadb:11" "valkey:7" false $root null null "10.1.2.0/24"
            {} {} $sender_bundle $receiver_bundle
    )
    let lines = (read-stack-env-lines $env_file)
    let results = [
        (assert-list-contains $lines
            "SENDER_REVAD_IMAGE=ghcr.io/example/cernbox-revad:sender"
            "stack.env has SENDER_REVAD_IMAGE")
        (assert-list-contains $lines
            "RECEIVER_REVAD_IMAGE=ghcr.io/example/cernbox-revad:receiver"
            "stack.env has RECEIVER_REVAD_IMAGE")
        (assert-list-contains $lines
            "SENDER_IDP_IMAGE=ghcr.io/example/idp:sender"
            "stack.env has SENDER_IDP_IMAGE")
        (assert-list-contains $lines
            "RECEIVER_IDP_IMAGE=ghcr.io/example/idp:receiver"
            "stack.env has RECEIVER_IDP_IMAGE")
    ]
    rm -rf $dirs.base
    $results
}

def test-resolve-receiver-images-bundle-services [] {
    test-log "\n[test-resolve-receiver-images-bundle-services]"
    let sender_imgs = (resolve-images "cernbox" "v11" --matrix-key "login__cernbox" --flow-id "login")
    let recv_imgs = (resolve-receiver-images "cernbox" "v11" --matrix-key "login__cernbox" --flow-id "login")
    [
        (assert-truthy (not ($recv_imgs.bundle | is-empty))
            "resolve-receiver-images returns non-empty bundle for cernbox")
        (assert-eq ($recv_imgs.bundle_services | get revad) "receiver-revad-gateway"
            "receiver revad service label is role-prefixed")
        (assert-eq ($recv_imgs.bundle_services | get idp) "receiver-idp"
            "receiver idp service label is role-prefixed")
        (assert-eq ($sender_imgs.bundle_services | get revad) "sender-revad-gateway"
            "sender revad service label unchanged")
        (assert-eq ($recv_imgs.bundle.revad) ($sender_imgs.bundle.revad)
            "receiver revad ref resolves from same bundle spec")
    ]
}

def test-cernbox-receiver-cookbook-stack-env-parity [] {
    test-log "\n[test-cernbox-receiver-cookbook-stack-env-parity]"
    let root = (get-ocmts-root)
    let cookbook_path = ($root | path join $CERNBOX_RECEIVER_COOKBOOK)
    let cookbook = (open -r $cookbook_path)
    let recv_imgs = (resolve-receiver-images "cernbox" "v11" --matrix-key "login__cernbox" --flow-id "login")
    let dirs = (make-art-inputs)
    let env_file = (
        write-two-party-env
            $dirs.art_inputs "cernbox" "cernbox" "v11" "v11"
            "ghcr.io/example/cernbox-web:sender" $recv_imgs.platform
            "mariadb:11" "valkey:7" false $root null null "10.1.2.0/24"
            {} {} {} $recv_imgs.bundle
    )
    let lines = (read-stack-env-lines $env_file)
    let revad_line = $"RECEIVER_REVAD_IMAGE=($recv_imgs.bundle.revad)"
    let idp_line = $"RECEIVER_IDP_IMAGE=($recv_imgs.bundle.idp)"
    let results = [
        (assert-string-contains $cookbook "${RECEIVER_REVAD_IMAGE}"
            "cernbox.receiver.yml references RECEIVER_REVAD_IMAGE placeholder")
        (assert-string-contains $cookbook "${RECEIVER_IDP_IMAGE}"
            "cernbox.receiver.yml references RECEIVER_IDP_IMAGE placeholder")
        (assert-list-contains $lines $revad_line
            "stack.env receiver revad ref matches resolve-receiver-images bundle")
        (assert-list-contains $lines $idp_line
            "stack.env receiver idp ref matches resolve-receiver-images bundle")
    ]
    rm -rf $dirs.base
    $results
}

def test-write-compose-overlays-forwards-empty-bundles-to-topology [] {
    test-log "\n[test-write-compose-overlays-forwards-empty-bundles-to-topology]"
    let root = (get-ocmts-root)
    let artifacts_base = ($nu.temp-dir | path join $"bundle-2p-render-(random uuid)")
    mkdir ($artifacts_base | path join "compose" "inputs")
    let sender_imgs = (
        resolve-images "nextcloud" "v32" --matrix-key "share-with__nextcloud__nextcloud" --flow-id "share-with"
    )
    let recv_imgs = (
        resolve-receiver-images "nextcloud" "v32" --matrix-key "share-with__nextcloud__nextcloud" --flow-id "share-with"
    )
    let overlay = (
        write-compose-overlays
            "share-with" "nextcloud" "cell-share-nc-v32" $FIXTURE_EXEC_ID
            $sender_imgs.platform
            $sender_imgs.cypress_ci $sender_imgs.cypress_dev
            $sender_imgs.mariadb $sender_imgs.valkey
            "cypress/e2e/share-with/index.cy.ts" "chrome" false
            $root $artifacts_base
            "nextcloud" $recv_imgs.platform "mitmproxy:test"
            "v32" "v32"
    )
    let lines = (read-stack-env-lines $overlay.env_file)
    let sender_line = $"SENDER_IMAGE=($sender_imgs.platform)"
    let receiver_line = $"RECEIVER_IMAGE=($recv_imgs.platform)"
    let results = [
        (assert-truthy $overlay.is_two_party "render routes two-party path")
        (assert-list-contains $lines $sender_line
            "render forwards empty bundles; topology resolves sender images")
        (assert-list-contains $lines $receiver_line
            "render forwards empty bundles; topology resolves receiver images")
        (assert-truthy ($sender_imgs.bundle | is-empty)
            "nextcloud sender bundle empty as expected")
        (assert-truthy ($recv_imgs.bundle | is-empty)
            "nextcloud receiver bundle empty as expected")
    ]
    cleanup-overlay-artifacts $artifacts_base $FIXTURE_EXEC_ID
    $results
}

def test-write-compose-overlays-forwards-two-party-bundles [] {
    test-log "\n[test-write-compose-overlays-forwards-two-party-bundles]"
    let root = (get-ocmts-root)
    let artifacts_base = ($nu.temp-dir | path join $"bundle-2p-render-pass-(random uuid)")
    mkdir ($artifacts_base | path join "compose" "inputs")
    let sender_imgs = (
        resolve-images "nextcloud" "v32" --matrix-key "share-with__nextcloud__nextcloud" --flow-id "share-with"
    )
    let recv_imgs = (
        resolve-receiver-images "nextcloud" "v32" --matrix-key "share-with__nextcloud__nextcloud" --flow-id "share-with"
    )
    let cernbox_sender = (
        resolve-images "cernbox" "v11" --matrix-key "login__cernbox" --flow-id "login"
    )
    let cernbox_receiver = (
        resolve-receiver-images "cernbox" "v11" --matrix-key "login__cernbox" --flow-id "login"
    )
    let overlay = (
        write-compose-overlays
            "share-with" "nextcloud" "cell-share-nc-v32" $FIXTURE_EXEC_ID
            $sender_imgs.platform
            $sender_imgs.cypress_ci $sender_imgs.cypress_dev
            $sender_imgs.mariadb $sender_imgs.valkey
            "cypress/e2e/share-with/index.cy.ts" "chrome" false
            $root $artifacts_base
            "nextcloud" $recv_imgs.platform "mitmproxy:test"
            "v32" "v32"
            $cernbox_sender.bundle $cernbox_receiver.bundle
    )
    let lines = (read-stack-env-lines $overlay.env_file)
    let receiver_revad = $"RECEIVER_REVAD_IMAGE=($cernbox_receiver.bundle.revad)"
    let sender_revad = $"SENDER_REVAD_IMAGE=($cernbox_sender.bundle.revad)"
    let results = [
        (assert-list-contains $lines $sender_revad
            "render forwards caller-passed sender bundle slots")
        (assert-list-contains $lines $receiver_revad
            "render forwards caller-passed receiver bundle slots")
    ]
    cleanup-overlay-artifacts $artifacts_base $FIXTURE_EXEC_ID
    $results
}

def test-write-two-party-overlays-resolves-empty-bundles [] {
    test-log "\n[test-write-two-party-overlays-resolves-empty-bundles]"
    let root = (get-ocmts-root)
    let artifacts_base = ($nu.temp-dir | path join $"bundle-2p-topo-(random uuid)")
    mkdir ($artifacts_base | path join "compose" "inputs")
    let sender_imgs = (
        resolve-images "nextcloud" "v32" --matrix-key "share-with__nextcloud__nextcloud" --flow-id "share-with"
    )
    let recv_imgs = (
        resolve-receiver-images "nextcloud" "v32" --matrix-key "share-with__nextcloud__nextcloud" --flow-id "share-with"
    )
    let overlay = (
        write-two-party-overlays
            "share-with" "nextcloud" "nextcloud" "cell-share-nc-v32" $FIXTURE_EXEC_ID
            $sender_imgs.platform $recv_imgs.platform "mitmproxy:test"
            $sender_imgs.cypress_ci $sender_imgs.cypress_dev
            $sender_imgs.mariadb $sender_imgs.valkey
            "cypress/e2e/share-with/index.cy.ts" "chrome" false
            $root $artifacts_base
            "v32" "v32"
    )
    let lines = (read-stack-env-lines $overlay.env_file)
    let sender_line = $"SENDER_IMAGE=($sender_imgs.platform)"
    let results = [
        (assert-truthy $overlay.is_two_party "topology two-party overlay flag")
        (assert-list-contains $lines $sender_line
            "topology resolves bundles when args empty")
        (assert-truthy (
            $lines | where {|l| $l | str starts-with "SENDER_REVAD_IMAGE="} | is-empty
        ) "topology empty-bundle resolve omits sender revad slot")
    ]
    cleanup-overlay-artifacts $artifacts_base $FIXTURE_EXEC_ID
    $results
}

def test-write-two-party-overlays-threads-passed-bundles [] {
    test-log "\n[test-write-two-party-overlays-threads-passed-bundles]"
    let root = (get-ocmts-root)
    let artifacts_base = ($nu.temp-dir | path join $"bundle-2p-topo-pass-(random uuid)")
    mkdir ($artifacts_base | path join "compose" "inputs")
    let sender_imgs = (
        resolve-images "nextcloud" "v32" --matrix-key "share-with__nextcloud__nextcloud" --flow-id "share-with"
    )
    let recv_imgs = (
        resolve-receiver-images "nextcloud" "v32" --matrix-key "share-with__nextcloud__nextcloud" --flow-id "share-with"
    )
    let cernbox_sender = (
        resolve-images "cernbox" "v11" --matrix-key "login__cernbox" --flow-id "login"
    )
    let cernbox_receiver = (
        resolve-receiver-images "cernbox" "v11" --matrix-key "login__cernbox" --flow-id "login"
    )
    let overlay = (
        write-two-party-overlays
            "share-with" "nextcloud" "nextcloud" "cell-share-nc-v32" $FIXTURE_EXEC_ID
            $sender_imgs.platform $recv_imgs.platform "mitmproxy:test"
            $sender_imgs.cypress_ci $sender_imgs.cypress_dev
            $sender_imgs.mariadb $sender_imgs.valkey
            "cypress/e2e/share-with/index.cy.ts" "chrome" false
            $root $artifacts_base
            "v32" "v32"
            $cernbox_sender.bundle $cernbox_receiver.bundle
    )
    let lines = (read-stack-env-lines $overlay.env_file)
    let receiver_revad = $"RECEIVER_REVAD_IMAGE=($cernbox_receiver.bundle.revad)"
    let sender_revad = $"SENDER_REVAD_IMAGE=($cernbox_sender.bundle.revad)"
    let results = [
        (assert-list-contains $lines $sender_revad
            "topology threads render-passed sender bundle slots")
        (assert-list-contains $lines $receiver_revad
            "topology threads render-passed receiver bundle slots")
    ]
    cleanup-overlay-artifacts $artifacts_base $FIXTURE_EXEC_ID
    $results
}

# setup-run-context threads both bundles through context -> render -> topology.
def test-setup-run-context-two-party-bundle-passthrough [] {
    test-log "\n[test-setup-run-context-two-party-bundle-passthrough]"
    let docker_check = (try {
        ^docker version | complete
    } catch {
        {exit_code: 127, stdout: "", stderr: ""}
    })
    if $docker_check.exit_code != 0 {
        test-log "  skip: no docker daemon for subnet preflight"
        return [(SKIP "setup-run-context two-party full chain: no docker daemon for subnet preflight")]
    }
    let real_root = (get-ocmts-root)
    let fixture_root = ($nu.temp-dir | path join $"bundle-2p-ctx-fixture-(random uuid)")
    write-cernbox-two-party-fixture-root $real_root $fixture_root
    let exec_id = "20260101t000000-ddccbbaa"
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
    let ctx = (
        with-env {OCMTS_ROOT: $fixture_root} {
            setup-run-context "share-with" "cernbox" "v11" "chrome" false "cernbox" "v11" --execution-id $exec_id
        }
    )
    let lines = (read-stack-env-lines $ctx.env_file)
    let sender_revad = $"SENDER_REVAD_IMAGE=($sender_imgs.bundle.revad)"
    let sender_idp = $"SENDER_IDP_IMAGE=($sender_imgs.bundle.idp)"
    let receiver_revad = $"RECEIVER_REVAD_IMAGE=($recv_imgs.bundle.revad)"
    let receiver_idp = $"RECEIVER_IDP_IMAGE=($recv_imgs.bundle.idp)"
    let results = [
        (assert-truthy $ctx.is_two_party "setup-run-context two-party overlay flag")
        (assert-truthy (not ($ctx.images.bundle | is-empty))
            "setup-run-context images include non-empty sender bundle")
        (assert-truthy (not ($ctx.images.receiver_bundle | is-empty))
            "setup-run-context images include non-empty receiver_bundle")
        (assert-eq ($ctx.images.receiver_bundle_services | get revad) "receiver-revad-gateway"
            "setup-run-context carries receiver revad service name")
        (assert-eq ($ctx.images.receiver_bundle_services | get idp) "receiver-idp"
            "setup-run-context carries receiver idp service name")
        (assert-list-contains $lines $sender_revad
            "setup-run-context stack.env has resolved sender revad image")
        (assert-list-contains $lines $sender_idp
            "setup-run-context stack.env has resolved sender idp image")
        (assert-list-contains $lines $receiver_revad
            "setup-run-context stack.env has resolved receiver revad image")
        (assert-list-contains $lines $receiver_idp
            "setup-run-context stack.env has resolved receiver idp image")
    ]
    rm -rf $ctx.artifacts_base
    rm -rf (execution-temp-path $exec_id)
    let marker = ($fixture_root | path join "artifacts" "share-with" "cernbox-v11-cernbox-v11" "LAST_EXECUTION_ID")
    if ($marker | path exists) {
        rm $marker
    }
    rm -rf $fixture_root
    $results
}

def test-cernbox-two-party-overlay-bundle-and-cookbook-e2e [] {
    test-log "\n[test-cernbox-two-party-overlay-bundle-and-cookbook-e2e]"
    let real_root = (get-ocmts-root)
    let fixture_root = ($nu.temp-dir | path join $"bundle-2p-cernbox-fixture-(random uuid)")
    write-cernbox-two-party-fixture-root $real_root $fixture_root
    let artifacts_base = ($nu.temp-dir | path join $"bundle-2p-cernbox-overlay-(random uuid)")
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
            write-two-party-overlays "share-with" "cernbox" "cernbox" "cell-share-cernbox-v11" $FIXTURE_EXEC_ID $sender_imgs.platform $recv_imgs.platform "mitmproxy:test" $sender_imgs.cypress_ci $sender_imgs.cypress_dev $sender_imgs.mariadb $sender_imgs.valkey "cypress/e2e/share-with/index.cy.ts" "chrome" false $fixture_root $artifacts_base "v11" "v11" $sender_imgs.bundle $recv_imgs.bundle
        }
    )
    let lines = (read-stack-env-lines $overlay.env_file)
    let source_sender = (read-text ($real_root | path join $CERNBOX_SENDER_COOKBOOK))
    let source_receiver = (read-text ($real_root | path join $CERNBOX_RECEIVER_COOKBOOK))
    let overlay_sender = (read-text ($overlay.compose_d | path join "sender.yml"))
    let overlay_receiver = (read-text ($overlay.compose_d | path join "receiver.yml"))
    let art_sender = (read-text ($overlay.art_inputs | path join "sender.yml"))
    let art_receiver = (read-text ($overlay.art_inputs | path join "receiver.yml"))
    let revad_line = $"RECEIVER_REVAD_IMAGE=($recv_imgs.bundle.revad)"
    let idp_line = $"RECEIVER_IDP_IMAGE=($recv_imgs.bundle.idp)"
    let sender_revad = $"SENDER_REVAD_IMAGE=($sender_imgs.bundle.revad)"
    let results = [
        (assert-truthy (not ($recv_imgs.bundle | is-empty))
            "cernbox receiver bundle resolved for overlay path")
        (assert-list-contains $lines $revad_line
            "overlay stack.env has receiver revad bundle ref")
        (assert-list-contains $lines $idp_line
            "overlay stack.env has receiver idp bundle ref")
        (assert-list-contains $lines $sender_revad
            "overlay stack.env has sender revad bundle ref")
        (assert-eq $overlay_sender $source_sender
            "compose_d sender.yml mirrors cernbox.sender.yml cookbook")
        (assert-eq $overlay_receiver $source_receiver
            "compose_d receiver.yml mirrors cernbox.receiver.yml cookbook")
        (assert-eq $art_sender $source_sender
            "art_inputs sender.yml copied from overlay compose_d")
        (assert-eq $art_receiver $source_receiver
            "art_inputs receiver.yml copied from overlay compose_d")
        (assert-string-contains $overlay_sender "REVAD_OCMSHARES_JSON_FILE=/var/tmp/reva/shares.json"
            "overlay sender.yml keeps REVAD_OCMSHARES_JSON_FILE for OCM shares")
        (assert-string-contains $overlay_sender "sender-reva-ocmshares:/var/tmp/reva"
            "overlay sender.yml mounts sender-reva-ocmshares volume for OCM shares")
        (assert-string-contains $overlay_receiver "REVAD_OCMSHARES_JSON_FILE=/var/tmp/reva/shares.json"
            "overlay receiver.yml keeps REVAD_OCMSHARES_JSON_FILE for OCM shares")
        (assert-string-contains $overlay_receiver "receiver-reva-ocmshares:/var/tmp/reva"
            "overlay receiver.yml mounts receiver-reva-ocmshares volume for OCM shares")
        (assert-string-contains $overlay_receiver "${RECEIVER_REVAD_IMAGE}"
            "overlay receiver.yml keeps RECEIVER_REVAD_IMAGE placeholder")
        (assert-string-contains $overlay_receiver "${RECEIVER_IDP_IMAGE}"
            "overlay receiver.yml keeps RECEIVER_IDP_IMAGE placeholder")
        (assert-string-contains $overlay_receiver "${RECEIVER_IDP_ORIGIN}"
            "overlay receiver.yml keeps RECEIVER_IDP_ORIGIN placeholder")
    ]
    cleanup-overlay-artifacts $artifacts_base $FIXTURE_EXEC_ID $fixture_root
    $results
}

def main [] {
    test-log "=== compose/bundle-two-party Tests ==="
    let results = (
        (test-write-two-party-env-bundle-lines)
        | append (test-resolve-receiver-images-bundle-services)
        | append (test-cernbox-receiver-cookbook-stack-env-parity)
        | append (test-write-compose-overlays-forwards-empty-bundles-to-topology)
        | append (test-write-compose-overlays-forwards-two-party-bundles)
        | append (test-write-two-party-overlays-resolves-empty-bundles)
        | append (test-write-two-party-overlays-threads-passed-bundles)
        | append (test-cernbox-two-party-overlay-bundle-and-cookbook-e2e)
        | append (test-setup-run-context-two-party-bundle-passthrough)
    ) | flatten
    run-suite "compose/bundle-two-party" $SUITE_PATH $results
}
