# One-party bundle wiring: stack.env SENDER_*_IMAGE lines, cookbook parity,
# render -> topology pass-through, and setup-run-context bundle passthrough.
# Run: nu scripts/tests/compose/bundle-one-party.nu

const SUITE_PATH = path self

use ../../lib/compose/render.nu [write-compose-overlays]
use ../../lib/domain/core/ocmts-root.nu [get-ocmts-root]
use ../../lib/images/resolve.nu [resolve-images]
use ../../lib/run/execution-id.nu [execution-temp-path]
use ../../lib/services/context.nu [setup-run-context]
use ../../lib/tests/assert.nu *
use ../../lib/tests/runner.nu [run-suite]

const FIXTURE_EXEC_ID = "20260101t000000-aabbccdd"
const CERNBOX_COOKBOOK = "config/compose/cookbooks/cernbox.sender.yml"

def read-stack-env-lines [env_file: string] {
    (open $env_file | lines | each {|l| ($l | str trim)} | where {|l| not ($l | is-empty)})
}

def make-artifacts-base [] {
    let base = ($nu.temp-dir | path join $"bundle-1p-test-(random uuid)")
    mkdir ($base | path join "compose" "inputs")
    $base
}

def cleanup-overlay-artifacts [artifacts_base: string, execution_id: string] {
    rm -rf $artifacts_base
    rm -rf (execution-temp-path $execution_id)
}

# write-compose-overlays (render -> topology-one-party) emits bundle env lines.
def test-write-compose-overlays-bundle-env-lines [] {
    test-log "\n[test-write-compose-overlays-bundle-env-lines]"
    let root = (get-ocmts-root)
    let artifacts_base = (make-artifacts-base)
    let bundle = {
        revad: "ghcr.io/example/cernbox-revad:test",
        idp: "ghcr.io/example/idp:test",
    }
    let overlay = (
        write-compose-overlays
            "login" "cernbox" "cell-login-cernbox-v11" $FIXTURE_EXEC_ID
            "ghcr.io/example/cernbox-web:test"
            "cypress:ci" "cypress:dev"
            "mariadb:11" "valkey:7"
            "cypress/e2e/login/index.cy.ts" "chrome" false
            $root $artifacts_base
            "" "" "" "login" "v11" "" $bundle
    )
    let lines = (read-stack-env-lines $overlay.env_file)
    let results = [
        (assert-list-contains $lines
            "SENDER_REVAD_IMAGE=ghcr.io/example/cernbox-revad:test"
            "stack.env has SENDER_REVAD_IMAGE")
        (assert-list-contains $lines
            "SENDER_IDP_IMAGE=ghcr.io/example/idp:test"
            "stack.env has SENDER_IDP_IMAGE")
        (assert-truthy ($overlay.is_two_party == false) "one-party overlay flag")
    ]
    cleanup-overlay-artifacts $artifacts_base $FIXTURE_EXEC_ID
    $results
}

# Cookbook placeholders match config bundle keys and resolved stack.env values.
def test-cernbox-cookbook-stack-env-parity [] {
    test-log "\n[test-cernbox-cookbook-stack-env-parity]"
    let root = (get-ocmts-root)
    let cookbook_path = ($root | path join $CERNBOX_COOKBOOK)
    let cookbook = (open -r $cookbook_path)
    let imgs = (resolve-images "cernbox" "v11" --scenario "login" --flow-id "login")
    let artifacts_base = (make-artifacts-base)
    let overlay = (
        write-compose-overlays
            "login" "cernbox" "cell-login-cernbox-v11" $FIXTURE_EXEC_ID
            $imgs.platform $imgs.cypress_ci $imgs.cypress_dev
            $imgs.mariadb $imgs.valkey
            "cypress/e2e/login/index.cy.ts" "chrome" false
            $root $artifacts_base
            "" "" "" "login" "v11" "" $imgs.bundle
    )
    let lines = (read-stack-env-lines $overlay.env_file)
    let revad_line = $"SENDER_REVAD_IMAGE=($imgs.bundle.revad)"
    let idp_line = $"SENDER_IDP_IMAGE=($imgs.bundle.idp)"
    let results = [
        (assert-string-contains $cookbook "${SENDER_REVAD_IMAGE}"
            "cernbox.sender.yml references SENDER_REVAD_IMAGE placeholder")
        (assert-string-contains $cookbook "${SENDER_IDP_IMAGE}"
            "cernbox.sender.yml references SENDER_IDP_IMAGE placeholder")
        (assert-list-contains $lines $revad_line
            "stack.env revad ref matches resolve-images bundle")
        (assert-list-contains $lines $idp_line
            "stack.env idp ref matches resolve-images bundle")
    ]
    cleanup-overlay-artifacts $artifacts_base $FIXTURE_EXEC_ID
    $results
}

# setup-run-context passes images.bundle through to stack.env (full chain).
def test-setup-run-context-bundle-passthrough [] {
    test-log "\n[test-setup-run-context-bundle-passthrough]"
    let docker_check = (try {
        ^docker version | complete
    } catch {
        {exit_code: 127, stdout: "", stderr: ""}
    })
    if $docker_check.exit_code != 0 {
        test-log "  skip: no docker daemon for subnet preflight"
        return [(SKIP "setup-run-context full chain: no docker daemon for subnet preflight")]
    }
    let root = (get-ocmts-root)
    let exec_id = "20260101t000000-bbccddee"
    let imgs = (resolve-images "cernbox" "v11" --scenario "login" --flow-id "login")
    let ctx = (
        setup-run-context "login-cernbox" "cernbox" "v11" "chrome" false
            --execution-id $exec_id
    )
    let lines = (read-stack-env-lines $ctx.env_file)
    let revad_line = $"SENDER_REVAD_IMAGE=($imgs.bundle.revad)"
    let idp_line = $"SENDER_IDP_IMAGE=($imgs.bundle.idp)"
    let results = [
        (assert-truthy (not ($ctx.images.bundle | is-empty))
            "setup-run-context images include non-empty bundle")
        (assert-eq ($ctx.images.bundle_services | get revad) "sender-revad-gateway"
            "setup-run-context carries revad service name")
        (assert-eq ($ctx.images.bundle_services | get idp) "idp"
            "setup-run-context carries idp service name")
        (assert-list-contains $lines $revad_line
            "setup-run-context stack.env has resolved revad image")
        (assert-list-contains $lines $idp_line
            "setup-run-context stack.env has resolved idp image")
    ]
    rm -rf $ctx.artifacts_base
    rm -rf (execution-temp-path $exec_id)
    let marker = ($root | path join "artifacts" "login" "cernbox-v11" "LAST_EXECUTION_ID")
    if ($marker | path exists) {
        rm $marker
    }
    $results
}

def main [] {
    test-log "=== compose/bundle-one-party Tests ==="
    let results = (
        (test-write-compose-overlays-bundle-env-lines)
        | append (test-cernbox-cookbook-stack-env-parity)
        | append (test-setup-run-context-bundle-passthrough)
    ) | flatten
    run-suite "compose/bundle-one-party" $SUITE_PATH $results
}
