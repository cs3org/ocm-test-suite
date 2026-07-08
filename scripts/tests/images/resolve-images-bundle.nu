# resolve-images bundle reduction tests for cernbox/v11 and non-bundle platforms.
# Proves bundle slots resolve independently from the main platform image.
# Run: nu scripts/tests/images/resolve-images-bundle.nu

const SUITE_PATH = path self

use ../../lib/images/resolve.nu [resolve-images]
use ../../lib/tests/assert.nu *
use ../../lib/tests/runner.nu [run-suite]

const CERNBOX_WEB_DEFAULT = "ghcr.io/mahdibaghbani/containers/cernbox-web:master"
const CERNBOX_REVAD_DEFAULT = "ghcr.io/mahdibaghbani/containers/cernbox-revad:master-development"
const CERNBOX_IDP_DEFAULT = "ghcr.io/mahdibaghbani/containers/idp:v26.4.2"
const NEXTCLOUD_V35_HUB_WEBAPP_SHARE = "ghcr.io/mahdibaghbani/containers/jupyterhub:webapp-share"

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

def test-cernbox-v11-bundle-keys-and-defaults [] {
    test-log "\n[test-cernbox-v11-bundle-keys-and-defaults]"
    let imgs = (
        with-env (leaked-cernbox-image-env-mask) {
            resolve-images "cernbox" "v11"
        }
    )
    let bundle_cols = ($imgs.bundle | columns)
    [
        (assert-eq $imgs.platform $CERNBOX_WEB_DEFAULT "cernbox/v11 platform default")
        (assert-eq ($bundle_cols | sort) ["idp" "revad"] "bundle has revad and idp slots")
        (assert-eq ($imgs.bundle | get revad) $CERNBOX_REVAD_DEFAULT "revad default ref")
        (assert-eq ($imgs.bundle | get idp) $CERNBOX_IDP_DEFAULT "idp default ref")
        (assert-eq ($imgs.bundle_services | get revad) "sender-revad-gateway"
            "revad slot maps to real compose service name")
        (assert-eq ($imgs.bundle_services | get idp) "sender-idp"
            "idp slot maps to real compose service name")
    ]
}

def test-cernbox-v11-bundle-env-override-precedence [] {
    test-log "\n[test-cernbox-v11-bundle-env-override-precedence]"
    let custom_revad = "ghcr.io/example/cernbox-revad:override"
    let imgs = (
        with-env (leaked-cernbox-image-env-mask | merge { OCMTS_CERNBOX_REVAD_IMAGE: $custom_revad }) {
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
        with-env (leaked-cernbox-image-env-mask | merge { OCMTS_CERNBOX_IDP_IMAGE: $custom_idp }) {
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

def test-cernbox-v11-web-and-bundle-env-override-independence [] {
    test-log "\n[test-cernbox-v11-web-and-bundle-env-override-independence]"
    let custom_web = "ghcr.io/example/cernbox-web:override"
    let custom_revad = "ghcr.io/example/cernbox-revad:override"
    let imgs = (
        with-env (
            leaked-cernbox-image-env-mask
            | merge {
                OCMTS_CERNBOX_WEB_V11_IMAGE: $custom_web
                OCMTS_CERNBOX_REVAD_IMAGE: $custom_revad
            }
        ) {
            resolve-images "cernbox" "v11"
        }
    )
    [
        (assert-eq $imgs.platform $custom_web
            "OCMTS_CERNBOX_WEB_V11_IMAGE overrides platform web ref independently of bundle")
        (assert-eq ($imgs.bundle | get revad) $custom_revad
            "OCMTS_CERNBOX_REVAD_IMAGE overrides revad slot independently of platform web")
        (assert-eq ($imgs.bundle | get idp) $CERNBOX_IDP_DEFAULT
            "idp bundle slot unchanged when only web and revad envs are set")
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

def test-nextcloud-v35-login-no-hub-bundle [] {
    test-log "\n[test-nextcloud-v35-login-no-hub-bundle]"
    let imgs = (
        resolve-images "nextcloud" "v35"
            --matrix-key "login__nextcloud" --flow-id "login"
    )
    [
        (assert-truthy (($imgs.bundle | is-empty))
            "nextcloud/v35 login omits unresolved hub bundle slot")
        (assert-truthy (($imgs.bundle_services | is-empty))
            "nextcloud/v35 login omits hub bundle_services entry")
    ]
}

def test-nextcloud-v35-webapp-share-hub-bundle [] {
    test-log "\n[test-nextcloud-v35-webapp-share-hub-bundle]"
    let imgs = (
        resolve-images "nextcloud" "v35"
            --matrix-key "webapp-share__nextcloud__cernbox" --flow-id "webapp-share"
    )
    [
        (assert-eq ($imgs.bundle | columns | sort) ["hub"]
            "nextcloud/v35 webapp-share resolves hub bundle slot")
        (assert-eq ($imgs.bundle | get hub) $NEXTCLOUD_V35_HUB_WEBAPP_SHARE
            "nextcloud/v35 webapp-share hub default ref")
        (assert-eq ($imgs.bundle_services | get hub) "sender-hub"
            "hub slot maps to sender-hub compose service name")
    ]
}

def main [] {
    test-log "=== images/resolve-images-bundle Tests ==="
    let results = (
        (test-cernbox-v11-bundle-keys-and-defaults)
        | append (test-cernbox-v11-bundle-env-override-precedence)
        | append (test-cernbox-v11-bundle-idp-env-override-precedence)
        | append (test-cernbox-v11-web-and-bundle-env-override-independence)
        | append (test-nextcloud-v32-bundle-empty)
        | append (test-nextcloud-v35-login-no-hub-bundle)
        | append (test-nextcloud-v35-webapp-share-hub-bundle)
    ) | flatten
    run-suite "images/resolve-images-bundle" $SUITE_PATH $results
}
