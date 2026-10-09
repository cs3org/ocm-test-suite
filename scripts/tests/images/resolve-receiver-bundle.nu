# resolve-receiver-images bundle reduction tests for cernbox/v11.
# Run: nu scripts/tests/images/resolve-receiver-bundle.nu

const SUITE_PATH = path self

use ../../lib/images/resolve.nu [resolve-images resolve-receiver-images]
use ../../lib/tests/assert.nu *
use ../../lib/tests/runner.nu [run-suite]

const CERNBOX_REVAD_DEFAULT = "ghcr.io/mahdibaghbani/containers/cernbox-revad:master-development"
const CERNBOX_REVAD_WEBAPP_SHARE = "ghcr.io/mahdibaghbani/containers/cernbox-revad:ocm-webapp-share-development"
const CERNBOX_IDP_DEFAULT = "ghcr.io/mahdibaghbani/containers/idp:v26.4.2"
const CERNBOX_REGISTRY_DEFAULT = "nats:2.15.0-alpine3.22"

def leaked-cernbox-image-env-mask [] {
    [
        OCMTS_CERNBOX_WEB_V11_IMAGE
        OCMTS_CERNBOX_REVAD_IMAGE
        OCMTS_CERNBOX_REVAD_WEBAPP_SHARE_IMAGE
        OCMTS_CERNBOX_IDP_IMAGE
        OCMTS_CERNBOX_REGISTRY_IMAGE
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
        (assert-eq ($bundle_cols | sort) ["idp" "registry" "revad"]
            "receiver bundle has revad, idp, and registry slots")
        (assert-eq ($imgs.bundle | get revad) $CERNBOX_REVAD_DEFAULT "receiver revad default ref")
        (assert-eq ($imgs.bundle | get idp) $CERNBOX_IDP_DEFAULT "receiver idp default ref")
        (assert-eq ($imgs.bundle | get registry) $CERNBOX_REGISTRY_DEFAULT "receiver registry default ref")
        (assert-eq ($imgs.bundle_services | get revad) "receiver-revad-gateway"
            "receiver revad maps to receiver-revad-gateway")
        (assert-eq ($imgs.bundle_services | get idp) "receiver-idp"
            "receiver idp maps to receiver-idp")
        (assert-eq ($imgs.bundle_services | get registry) "receiver-revad-registry"
            "receiver registry maps to receiver-revad-registry")
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
        (assert-eq ($sender.bundle | get registry) $CERNBOX_REGISTRY_DEFAULT
            "sender registry ref is in the parity bundle")
        (assert-eq ($sender.bundle_services | get registry) "sender-revad-registry"
            "sender registry service label")
        (assert-eq ($receiver.bundle_services | get registry) "receiver-revad-registry"
            "receiver registry service label")
    ]
}

def test-receiver-registry-env-override [] {
    test-log "\n[test-receiver-registry-env-override]"
    let custom_registry = "localhost/ocmts/nats:receiver-registry"
    let imgs = (
        with-env (leaked-cernbox-image-env-mask | merge {
            OCMTS_CERNBOX_REGISTRY_IMAGE: $custom_registry
        }) {
            {
                login: (resolve-receiver-images "cernbox" "v11" --flow-id "login")
                share: (resolve-receiver-images "cernbox" "v11" --flow-id "webapp-share")
            }
        }
    )
    [
        (assert-eq ($imgs.login.bundle | get registry) $custom_registry
            "generic registry override applies to the login receiver bundle")
        (assert-eq ($imgs.share.bundle | get registry) $custom_registry
            "generic registry override applies to the webapp-share receiver bundle")
        (assert-eq ($imgs.login.bundle | get revad) $CERNBOX_REVAD_DEFAULT
            "login receiver revad unchanged when only registry env is set")
        (assert-eq ($imgs.share.bundle | get revad) $CERNBOX_REVAD_WEBAPP_SHARE
            "webapp-share receiver revad keeps its by_flow default")
        (assert-eq ($imgs.share.bundle | get idp) $CERNBOX_IDP_DEFAULT
            "receiver idp unchanged when only registry env is set")
    ]
}

def main [] {
    test-log "=== images/resolve-receiver-bundle Tests ==="
    let results = (
        (test-receiver-bundle-keys-and-role-labels)
        | append (test-sender-receiver-bundle-parity)
        | append (test-receiver-registry-env-override)
    ) | flatten
    run-suite "images/resolve-receiver-bundle" $SUITE_PATH $results
}
