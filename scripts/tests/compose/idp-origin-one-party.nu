# One-party IdP env emission: external-idp platforms (cernbox) get
# SENDER_IDP_HOST/ORIGIN + CYPRESS_sender_idp_origin/realm in stack.env from the
# platforms.nuon login SSOT; same-origin platforms (nextcloud) get none.
# Run: nu scripts/tests/compose/idp-origin-one-party.nu

const SUITE_PATH = path self

use ../../lib/compose/render.nu [write-compose-overlays]
use ../../lib/domain/core/ocmts-root.nu [get-ocmts-root]
use ../../lib/images/resolve.nu [resolve-images]
use ../../lib/run/execution-id.nu [execution-temp-path]
use ../../lib/tests/assert.nu *
use ../../lib/tests/runner.nu [run-suite]

const FIXTURE_EXEC_ID = "20260101t000000-ddeeff00"

def read-stack-env-lines [env_file: string] {
    (open $env_file | lines | each {|l| ($l | str trim)} | where {|l| not ($l | is-empty)})
}

def read-text [path: string] {
    open -r $path
}

def is-compose-top-level-service-line [line: string] {
    not (($line | parse --regex '^  [^\s].+:$' | is-empty))
}

def extract-compose-service-block [src: string, service: string] {
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

def assert-revad-proxy-env [compose: string, service: string, party_prefix: string] {
    let block = (extract-compose-service-block $compose $service)
    let label = $"($service) proxy env"
    [
        (assert-not-null $block $"($label) block exists")
        (assert-string-contains $block $"HTTP_PROXY=${($party_prefix)}_HTTP_PROXY}"
            $"($label) has HTTP_PROXY")
        (assert-string-contains $block $"HTTPS_PROXY=${($party_prefix)}_HTTPS_PROXY}"
            $"($label) has HTTPS_PROXY")
        (assert-string-contains $block $"NO_PROXY=${($party_prefix)}_NO_PROXY}"
            $"($label) has NO_PROXY")
    ]
}

const CERNBOX_SENDER_REVAD_PROXY_SERVICES = [
    "sender-revad-gateway"
    "sender-revad-dataprovider-ocm"
    "sender-revad-dataprovider-sciencemesh"
]

def make-artifacts-base [] {
    let base = ($nu.temp-dir | path join $"idp-origin-1p-test-(random uuid)")
    mkdir ($base | path join "compose" "inputs")
    $base
}

def cleanup [artifacts_base: string, execution_id: string] {
    rm -rf $artifacts_base
    rm -rf (execution-temp-path $execution_id)
}

# cernbox (external-idp) emits the IdP host/origin/realm trio from the SSOT.
def test-cernbox-emits-idp-env [] {
    test-log "\n[test-cernbox-emits-idp-env]"
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
            "" "" "" "v11" "" $bundle
    )
    let lines = (read-stack-env-lines $overlay.env_file)
    let runner_ci = (read-text ($overlay.compose_d | path join "runner-ci.yml"))
    let runner_dev = (read-text ($overlay.compose_d | path join "runner-dev.yml"))
    let overlay_sender = (read-text ($overlay.compose_d | path join "sender.yml"))
    let results = [
        (assert-list-contains $lines "SENDER_IDP_HOST=idp1.docker"
            "stack.env has SENDER_IDP_HOST=idp1.docker")
        (assert-list-contains $lines "SENDER_IDP_ORIGIN=https://idp1.docker"
            "stack.env has SENDER_IDP_ORIGIN=https://idp1.docker")
        (assert-list-contains $lines "CYPRESS_sender_idp_origin=https://idp1.docker"
            "stack.env has CYPRESS_sender_idp_origin")
        (assert-list-contains $lines "CYPRESS_sender_idp_realm=cernbox"
            "stack.env has CYPRESS_sender_idp_realm from SSOT")
        (assert-string-contains $runner_ci "CYPRESS_sender_idp_origin=https://idp1.docker"
            "runner-ci.yml has CYPRESS_sender_idp_origin")
        (assert-string-contains $runner_ci "CYPRESS_sender_idp_realm=cernbox"
            "runner-ci.yml has CYPRESS_sender_idp_realm")
        (assert-string-contains $runner_dev "CYPRESS_sender_idp_origin=https://idp1.docker"
            "runner-dev.yml has CYPRESS_sender_idp_origin")
        (assert-string-contains $runner_dev "CYPRESS_sender_idp_realm=cernbox"
            "runner-dev.yml has CYPRESS_sender_idp_realm")
    ]
    let proxy_results = (
        $CERNBOX_SENDER_REVAD_PROXY_SERVICES
        | each {|svc| assert-revad-proxy-env $overlay_sender $svc "SENDER"}
        | flatten
    )
    cleanup $artifacts_base $FIXTURE_EXEC_ID
    ($results | append $proxy_results)
}

# nextcloud (same-origin) emits no IdP env at all.
def test-nextcloud-omits-idp-env [] {
    test-log "\n[test-nextcloud-omits-idp-env]"
    let root = (get-ocmts-root)
    let artifacts_base = (make-artifacts-base)
    let overlay = (
        write-compose-overlays
            "login" "nextcloud" "cell-login-nextcloud-v32" $FIXTURE_EXEC_ID
            "ghcr.io/example/nextcloud:test"
            "cypress:ci" "cypress:dev"
            "mariadb:11" "valkey:7"
            "cypress/e2e/login/index.cy.ts" "chrome" false
            $root $artifacts_base
            "" "" "" "v32" "" {}
    )
    let lines = (read-stack-env-lines $overlay.env_file)
    let runner_ci = (read-text ($overlay.compose_d | path join "runner-ci.yml"))
    let runner_dev = (read-text ($overlay.compose_d | path join "runner-dev.yml"))
    let idp_lines = ($lines | where {|l|
        (($l | str starts-with "SENDER_IDP_")
            or ($l | str starts-with "CYPRESS_sender_idp_")
            or ($l | str starts-with "CYPRESS_receiver_idp_"))
    })
    let results = [
        (assert-truthy ($idp_lines | is-empty)
            "same-origin nextcloud emits no SENDER_IDP_* or CYPRESS_*_idp_* lines")
        (assert-truthy (not ($runner_ci | str contains "CYPRESS_sender_idp_origin="))
            "same-origin nextcloud runner-ci.yml omits CYPRESS_sender_idp_origin")
        (assert-truthy (not ($runner_ci | str contains "CYPRESS_sender_idp_realm="))
            "same-origin nextcloud runner-ci.yml omits CYPRESS_sender_idp_realm")
        (assert-truthy (not ($runner_dev | str contains "CYPRESS_sender_idp_origin="))
            "same-origin nextcloud runner-dev.yml omits CYPRESS_sender_idp_origin")
        (assert-truthy (not ($runner_dev | str contains "CYPRESS_sender_idp_realm="))
            "same-origin nextcloud runner-dev.yml omits CYPRESS_sender_idp_realm")
    ]
    cleanup $artifacts_base $FIXTURE_EXEC_ID
    $results
}

def main [] {
    test-log "=== compose/idp-origin-one-party Tests ==="
    let results = (
        (test-cernbox-emits-idp-env)
        | append (test-nextcloud-omits-idp-env)
    ) | flatten
    run-suite "compose/idp-origin-one-party" $SUITE_PATH $results
}
