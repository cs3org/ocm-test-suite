# resolve-receiver-images bundle reduction tests for cernbox/v11.
# Run: nu scripts/tests/images/resolve-receiver-bundle.nu

const SUITE_PATH = path self

use ../../lib/images/resolve.nu [resolve-images resolve-receiver-images]
use ../../lib/tests/assert.nu *
use ../../lib/tests/runner.nu [run-suite]

const CERNBOX_REVAD_DEFAULT = "ghcr.io/mahdibaghbani/containers/cernbox-revad:master-development"
const CERNBOX_IDP_DEFAULT = "ghcr.io/mahdibaghbani/containers/idp:v26.4.2"

def leaked-cernbox-image-env-mask [] {
    [
        OCMTS_CERNBOX_WEB_V11_IMAGE
        OCMTS_CERNBOX_REVAD_IMAGE
        OCMTS_CERNBOX_IDP_IMAGE
    ]
    | reduce --fold {} {|k, acc|
        if $k in $env { $acc | upsert $k null } else { $acc }
    }
}

def test-receiver-bundle-keys-and-role-labels [] {
    test-log "\n[test-receiver-bundle-keys-and-role-labels]"
    let imgs = (
        with-env (leaked-cernbox-image-env-mask) {
            resolve-receiver-images "cernbox" "v11"
        }
    )
    let bundle_cols = ($imgs.bundle | columns)
    [
        (assert-eq ($bundle_cols | sort) ["idp" "revad"] "receiver bundle has revad and idp slots")
        (assert-eq ($imgs.bundle | get revad) $CERNBOX_REVAD_DEFAULT "receiver revad default ref")
        (assert-eq ($imgs.bundle | get idp) $CERNBOX_IDP_DEFAULT "receiver idp default ref")
        (assert-eq ($imgs.bundle_services | get revad) "receiver-revad-gateway"
            "receiver revad maps to receiver-revad-gateway")
        (assert-eq ($imgs.bundle_services | get idp) "receiver-idp"
            "receiver idp maps to receiver-idp")
    ]
}

def test-sender-receiver-bundle-parity [] {
    test-log "\n[test-sender-receiver-bundle-parity]"
    let sender = (
        with-env (leaked-cernbox-image-env-mask) {
            resolve-images "cernbox" "v11"
        }
    )
    let receiver = (
        with-env (leaked-cernbox-image-env-mask) {
            resolve-receiver-images "cernbox" "v11"
        }
    )
    [
        (assert-eq $sender.bundle $receiver.bundle
            "sender and receiver bundle refs match for cernbox v11")
        (assert-eq ($sender.bundle_services | get revad) "sender-revad-gateway"
            "sender revad service label")
        (assert-eq ($receiver.bundle_services | get revad) "receiver-revad-gateway"
            "receiver revad service label")
    ]
}

def main [] {
    test-log "=== images/resolve-receiver-bundle Tests ==="
    let results = (
        (test-receiver-bundle-keys-and-role-labels)
        | append (test-sender-receiver-bundle-parity)
    ) | flatten
    run-suite "images/resolve-receiver-bundle" $SUITE_PATH $results
}
