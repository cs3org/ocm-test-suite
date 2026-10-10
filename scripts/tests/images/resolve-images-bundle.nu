# resolve-images bundle reduction tests for cernbox/v11 and non-bundle platforms.
# Proves bundle slots resolve independently from the main platform image.
# Run: nu scripts/tests/images/resolve-images-bundle.nu

const SUITE_PATH = path self

use ../../lib/images/resolve.nu [resolve-images]
use ../../lib/tests/assert.nu *
use ../../lib/tests/runner.nu [run-suite]

const CERNBOX_WEB_DEFAULT = "ghcr.io/mahdibaghbani/containers/cernbox-web:master"
const CERNBOX_REVAD_DEFAULT = "ghcr.io/mahdibaghbani/containers/cernbox-revad:master-development"
const CERNBOX_REVAD_WEBAPP_SHARE = "ghcr.io/mahdibaghbani/containers/cernbox-revad:ocm-webapp-share-development"
const CERNBOX_IDP_DEFAULT = "ghcr.io/mahdibaghbani/containers/idp:v26.4.2"
const CERNBOX_REGISTRY_DEFAULT = "nats:2.15.0-alpine3.22"
const NEXTCLOUD_V35_HUB_WEBAPP_SHARE = "ghcr.io/mahdibaghbani/containers/jupyterhub:webapp-share"

def leaked-nextcloud-webapp-share-hub-env-mask [] {
    [OCMTS_NEXTCLOUD_V35_WEBAPP_SHARE_HUB_IMAGE]
    | reduce --fold {} {|k, acc|
        if $k in $env { $acc | upsert $k null } else { $acc }
    }
}

def leaked-cernbox-image-env-mask [] {
    [
        OCMTS_CERNBOX_WEB_V11_IMAGE
        OCMTS_CERNBOX_REVAD_IMAGE
        OCMTS_CERNBOX_REVAD_WEBAPP_SHARE_IMAGE
        OCMTS_CERNBOX_IDP_IMAGE
        OCMTS_CERNBOX_REGISTRY_IMAGE
        OCMTS_CERNBOX_WEB_V11_WEBAPP_SHARE_IMAGE
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
        (assert-eq ($bundle_cols | sort) ["idp" "registry" "revad"]
            "bundle has revad, idp, and registry slots")
        (assert-eq ($imgs.bundle | get revad) $CERNBOX_REVAD_DEFAULT "revad default ref")
        (assert-eq ($imgs.bundle | get idp) $CERNBOX_IDP_DEFAULT "idp default ref")
        (assert-eq ($imgs.bundle | get registry) $CERNBOX_REGISTRY_DEFAULT "registry default ref")
        (assert-eq ($imgs.bundle_services | get revad) "sender-revad-gateway"
            "revad slot maps to real compose service name")
        (assert-eq ($imgs.bundle_services | get idp) "sender-idp"
            "idp slot maps to real compose service name")
        (assert-eq ($imgs.bundle_services | get registry) "sender-revad-registry"
            "registry slot maps to sender-revad-registry")
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
        (assert-eq ($imgs.bundle | get registry) $CERNBOX_REGISTRY_DEFAULT
            "registry bundle slot unchanged when only revad env is set")
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
        (assert-eq ($imgs.bundle | get registry) $CERNBOX_REGISTRY_DEFAULT
            "registry bundle slot unchanged when only idp env is set")
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
        (assert-eq ($imgs.bundle | get registry) $CERNBOX_REGISTRY_DEFAULT
            "registry bundle slot unchanged when only web and revad envs are set")
    ]
}

def test-cernbox-v11-registry-env-override [] {
    test-log "\n[test-cernbox-v11-registry-env-override]"
    let custom_registry = "localhost/ocmts/nats:registry-override"
    let imgs = (
        with-env (leaked-cernbox-image-env-mask | merge {
            OCMTS_CERNBOX_REGISTRY_IMAGE: $custom_registry
        }) {
            resolve-images "cernbox" "v11"
        }
    )
    [
        (assert-eq ($imgs.bundle | get registry) $custom_registry
            "OCMTS_CERNBOX_REGISTRY_IMAGE overrides the registry slot")
        (assert-eq ($imgs.bundle | get revad) $CERNBOX_REVAD_DEFAULT
            "revad slot unchanged when only registry env is set")
        (assert-eq ($imgs.bundle | get idp) $CERNBOX_IDP_DEFAULT
            "idp slot unchanged when only registry env is set")
        (assert-eq ($imgs.bundle_services | get registry) "sender-revad-registry"
            "registry service name unchanged when the ref is overridden")
    ]
}

def test-cernbox-v11-registry-generic-on-webapp-share [] {
    test-log "\n[test-cernbox-v11-registry-generic-on-webapp-share]"
    let custom_registry = "localhost/ocmts/nats:registry-flow"
    let masked = (
        with-env (leaked-cernbox-image-env-mask) {
            {
                login: (resolve-images "cernbox" "v11" --flow-id "login")
                share: (resolve-images "cernbox" "v11" --flow-id "webapp-share")
            }
        }
    )
    let overridden = (
        with-env (leaked-cernbox-image-env-mask | merge {
            OCMTS_CERNBOX_REGISTRY_IMAGE: $custom_registry
        }) {
            {
                login: (resolve-images "cernbox" "v11" --flow-id "login")
                share: (resolve-images "cernbox" "v11" --flow-id "webapp-share")
            }
        }
    )
    [
        (assert-eq ($masked.login.bundle | get registry) $CERNBOX_REGISTRY_DEFAULT
            "login registry default is the generic nats ref")
        (assert-eq ($masked.share.bundle | get registry) $CERNBOX_REGISTRY_DEFAULT
            "webapp-share registry default stays the generic nats ref")
        (assert-eq ($masked.share.bundle | get revad) $CERNBOX_REVAD_WEBAPP_SHARE
            "webapp-share revad still uses its by_flow default")
        (assert-eq ($overridden.login.bundle | get registry) $custom_registry
            "generic registry override applies to login")
        (assert-eq ($overridden.share.bundle | get registry) $custom_registry
            "generic registry override applies to webapp-share")
        (assert-eq ($overridden.share.bundle | get revad) $CERNBOX_REVAD_WEBAPP_SHARE
            "registry override does not change the webapp-share revad ref")
    ]
}

def test-nextcloud-v33-bundle-empty [] {
    test-log "\n[test-nextcloud-v33-bundle-empty]"
    let imgs = (resolve-images "nextcloud" "v33")
    [
        (assert-truthy (($imgs.bundle | is-empty))
            "nextcloud/v33 has no bundle reduction")
        (assert-truthy (($imgs.bundle_services | is-empty))
            "nextcloud/v33 has no bundle_services map")
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

def test-nextcloud-v35-webapp-share-hub-bundle-nc-nc [] {
    test-log "\n[test-nextcloud-v35-webapp-share-hub-bundle-nc-nc]"
    let imgs = (
        resolve-images "nextcloud" "v35" --matrix-key "webapp-share__nextcloud__nextcloud" --flow-id "webapp-share"
    )
    [
        (assert-eq ($imgs.bundle | columns | sort) ["hub"]
            "NC->NC webapp-share resolves the same hub bundle slot")
        (assert-eq ($imgs.bundle | get hub) $NEXTCLOUD_V35_HUB_WEBAPP_SHARE
            "NC->NC webapp-share hub default ref matches NC->CB")
        (assert-eq ($imgs.bundle_services | get hub) "sender-hub"
            "NC->NC hub slot maps to sender-hub compose service name")
    ]
}

def test-nextcloud-v35-webapp-share-hub-env-override [] {
    test-log "\n[test-nextcloud-v35-webapp-share-hub-env-override]"
    let custom_hub = "localhost/ocmts/nextcloud-v35-webapp-share-hub:local"
    let imgs = (
        with-env (
            leaked-nextcloud-webapp-share-hub-env-mask
            | merge { OCMTS_NEXTCLOUD_V35_WEBAPP_SHARE_HUB_IMAGE: $custom_hub }
        ) {
            resolve-images "nextcloud" "v35" --matrix-key "webapp-share__nextcloud__nextcloud" --flow-id "webapp-share"
        }
    )
    [
        (assert-eq ($imgs.bundle | get hub) $custom_hub
            "OCMTS_NEXTCLOUD_V35_WEBAPP_SHARE_HUB_IMAGE overrides hub bundle slot")
        (assert-eq ($imgs.bundle_services | get hub) "sender-hub"
            "hub bundle_services entry unchanged when hub env override is set")
    ]
}

def main [] {
    test-log "=== images/resolve-images-bundle Tests ==="
    let results = (
        (test-cernbox-v11-bundle-keys-and-defaults)
        | append (test-cernbox-v11-bundle-env-override-precedence)
        | append (test-cernbox-v11-bundle-idp-env-override-precedence)
        | append (test-cernbox-v11-web-and-bundle-env-override-independence)
        | append (test-cernbox-v11-registry-env-override)
        | append (test-cernbox-v11-registry-generic-on-webapp-share)
        | append (test-nextcloud-v33-bundle-empty)
        | append (test-nextcloud-v35-login-no-hub-bundle)
        | append (test-nextcloud-v35-webapp-share-hub-bundle)
        | append (test-nextcloud-v35-webapp-share-hub-bundle-nc-nc)
        | append (test-nextcloud-v35-webapp-share-hub-env-override)
    ) | flatten
    run-suite "images/resolve-images-bundle" $SUITE_PATH $results
}
