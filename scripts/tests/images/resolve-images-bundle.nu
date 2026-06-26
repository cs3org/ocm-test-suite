# resolve-images bundle reduction tests for cernbox/v11 and non-bundle platforms.
# Run: nu scripts/tests/images/resolve-images-bundle.nu

const SUITE_PATH = path self

use ../../lib/images/resolve.nu [resolve-images]
use ../../lib/tests/assert.nu *
use ../../lib/tests/runner.nu [run-suite]

const CERNBOX_WEB_DEFAULT = "ghcr.io/mahdibaghbani/containers/cernbox-web:master"
const CERNBOX_REVAD_DEFAULT = "ghcr.io/mahdibaghbani/containers/cernbox-revad:master-development"
const CERNBOX_IDP_DEFAULT = "ghcr.io/mahdibaghbani/containers/idp:v26.4.2"

def test-cernbox-v11-bundle-keys-and-defaults [] {
    test-log "\n[test-cernbox-v11-bundle-keys-and-defaults]"
    let imgs = (resolve-images "cernbox" "v11")
    let bundle_cols = ($imgs.bundle | columns)
    [
        (assert-eq $imgs.platform $CERNBOX_WEB_DEFAULT "cernbox/v11 platform default")
        (assert-eq ($bundle_cols | sort) ["idp" "revad"] "bundle has revad and idp slots")
        (assert-eq ($imgs.bundle | get revad) $CERNBOX_REVAD_DEFAULT "revad default ref")
        (assert-eq ($imgs.bundle | get idp) $CERNBOX_IDP_DEFAULT "idp default ref")
        (assert-eq ($imgs.bundle_services | get revad) "sender-revad-gateway"
            "revad slot maps to real compose service name")
        (assert-eq ($imgs.bundle_services | get idp) "idp"
            "idp slot maps to real compose service name")
    ]
}

def test-cernbox-v11-bundle-env-override-precedence [] {
    test-log "\n[test-cernbox-v11-bundle-env-override-precedence]"
    let custom_revad = "ghcr.io/example/cernbox-revad:override"
    let imgs = (
        with-env { OCMTS_CERNBOX_REVAD_IMAGE: $custom_revad } {
            resolve-images "cernbox" "v11"
        }
    )
    [
        (assert-eq ($imgs.bundle | get revad) $custom_revad
            "OCMTS_CERNBOX_REVAD_IMAGE overrides revad bundle slot")
        (assert-eq ($imgs.bundle | get idp) $CERNBOX_IDP_DEFAULT
            "idp bundle slot unchanged when only revad env is set")
    ]
}

def test-cernbox-v11-bundle-idp-env-override-precedence [] {
    test-log "\n[test-cernbox-v11-bundle-idp-env-override-precedence]"
    let custom_idp = "ghcr.io/example/idp:override"
    let imgs = (
        with-env { OCMTS_CERNBOX_IDP_IMAGE: $custom_idp } {
            resolve-images "cernbox" "v11"
        }
    )
    [
        (assert-eq ($imgs.bundle | get idp) $custom_idp
            "OCMTS_CERNBOX_IDP_IMAGE overrides idp bundle slot")
        (assert-eq ($imgs.bundle | get revad) $CERNBOX_REVAD_DEFAULT
            "revad bundle slot unchanged when only idp env is set")
    ]
}

def test-nextcloud-v32-bundle-empty [] {
    test-log "\n[test-nextcloud-v32-bundle-empty]"
    let imgs = (resolve-images "nextcloud" "v32")
    [
        (assert-truthy (($imgs.bundle | is-empty))
            "nextcloud/v32 has no bundle reduction")
        (assert-truthy (($imgs.bundle_services | is-empty))
            "nextcloud/v32 has no bundle_services map")
    ]
}

def main [] {
    test-log "=== images/resolve-images-bundle Tests ==="
    let results = (
        (test-cernbox-v11-bundle-keys-and-defaults)
        | append (test-cernbox-v11-bundle-env-override-precedence)
        | append (test-cernbox-v11-bundle-idp-env-override-precedence)
        | append (test-nextcloud-v32-bundle-empty)
    ) | flatten
    run-suite "images/resolve-images-bundle" $SUITE_PATH $results
}
