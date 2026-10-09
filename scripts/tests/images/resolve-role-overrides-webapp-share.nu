# resolve-images / resolve-receiver-image webapp-share flow override tests.
# Proves nextcloud/v35 webapp-share by_flow scope wins over version scope for
# defaults, role env, and generic flow env vs version role env.
# Run: nu scripts/tests/images/resolve-role-overrides-webapp-share.nu

const SUITE_PATH = path self

use ../../lib/images/resolve.nu [resolve-images resolve-receiver-image resolve-receiver-images]
use ../../lib/tests/assert.nu *
use ../../lib/tests/runner.nu [run-suite]

const NEXTCLOUD_V35_WEBAPP_SHARE_DEFAULT = "ghcr.io/mahdibaghbani/containers/nextcloud-webapp:webapp-share"
const CERNBOX_REVAD_DEFAULT = "ghcr.io/mahdibaghbani/containers/cernbox-revad:master-development"
const CERNBOX_REVAD_WEBAPP_SHARE = "ghcr.io/mahdibaghbani/containers/cernbox-revad:ocm-webapp-share-development"
const CERNBOX_IDP_DEFAULT = "ghcr.io/mahdibaghbani/containers/idp:v26.4.2"
const CERNBOX_REGISTRY_DEFAULT = "nats:2.15.0-alpine3.22"

def leaked-role-image-env-mask [] {
    [
        OCMTS_NEXTCLOUD_V35_SENDER_IMAGE
        OCMTS_NEXTCLOUD_V35_RECEIVER_IMAGE
        OCMTS_NEXTCLOUD_V35_WEBAPP_SHARE_SENDER_IMAGE
        OCMTS_NEXTCLOUD_V35_WEBAPP_SHARE_RECEIVER_IMAGE
    ]
    | reduce --fold {} {|k, acc|
        if $k in $env { $acc | upsert $k null } else { $acc }
    }
}

def leaked-platform-image-env-mask [] {
    (
        leaked-role-image-env-mask
        | merge (
            [
                OCMTS_NEXTCLOUD_V35_IMAGE
                OCMTS_NEXTCLOUD_V35_WEBAPP_SHARE_IMAGE
            ]
            | reduce --fold {} {|k, acc|
                if $k in $env { $acc | upsert $k null } else { $acc }
            }
        )
    )
}

def leaked-cernbox-bundle-env-mask [] {
    [
        OCMTS_CERNBOX_REVAD_IMAGE
        OCMTS_CERNBOX_REVAD_WEBAPP_SHARE_IMAGE
        OCMTS_CERNBOX_IDP_IMAGE
        OCMTS_CERNBOX_REGISTRY_IMAGE
    ]
    | reduce --fold {} {|k, acc|
        if $k in $env { $acc | upsert $k null } else { $acc }
    }
}

def test-cernbox-registry-generic-override-all-flows [] {
    test-log "\n[test-cernbox-registry-generic-override-all-flows]"
    let custom_registry = "localhost/ocmts/nats:role-override"
    let got = (
        with-env (leaked-cernbox-bundle-env-mask | merge {
            OCMTS_CERNBOX_REGISTRY_IMAGE: $custom_registry
        }) {
            {
                login_sender: (resolve-images "cernbox" "v11" --flow-id "login")
                share_sender: (resolve-images "cernbox" "v11" --flow-id "webapp-share")
                login_receiver: (resolve-receiver-images "cernbox" "v11" --flow-id "login")
                share_receiver: (resolve-receiver-images "cernbox" "v11" --flow-id "webapp-share")
            }
        }
    )
    [
        (assert-eq ($got.login_sender.bundle | get registry) $custom_registry
            "generic registry override applies to login sender")
        (assert-eq ($got.share_sender.bundle | get registry) $custom_registry
            "generic registry override applies to webapp-share sender")
        (assert-eq ($got.login_receiver.bundle | get registry) $custom_registry
            "generic registry override applies to login receiver")
        (assert-eq ($got.share_receiver.bundle | get registry) $custom_registry
            "generic registry override applies to webapp-share receiver")
        (assert-eq ($got.login_sender.bundle | get registry) ($got.share_sender.bundle | get registry)
            "registry has no by_flow split between login and webapp-share")
    ]
}

def test-cernbox-revad-and-idp-override-semantics-unchanged [] {
    test-log "\n[test-cernbox-revad-and-idp-override-semantics-unchanged]"
    let custom_revad = "localhost/ocmts/cernbox-revad:generic"
    let custom_share_revad = "localhost/ocmts/cernbox-revad:webapp-share"
    let custom_idp = "localhost/ocmts/idp:override"
    let generic_only = (
        with-env (leaked-cernbox-bundle-env-mask | merge {
            OCMTS_CERNBOX_REVAD_IMAGE: $custom_revad
            OCMTS_CERNBOX_IDP_IMAGE: $custom_idp
        }) {
            resolve-images "cernbox" "v11" --flow-id "webapp-share"
        }
    )
    let flow_revad = (
        with-env (leaked-cernbox-bundle-env-mask | merge {
            OCMTS_CERNBOX_REVAD_IMAGE: $custom_revad
            OCMTS_CERNBOX_REVAD_WEBAPP_SHARE_IMAGE: $custom_share_revad
            OCMTS_CERNBOX_IDP_IMAGE: $custom_idp
        }) {
            resolve-images "cernbox" "v11" --flow-id "webapp-share"
        }
    )
    let login = (
        with-env (leaked-cernbox-bundle-env-mask | merge {
            OCMTS_CERNBOX_REVAD_IMAGE: $custom_revad
        }) {
            resolve-images "cernbox" "v11" --flow-id "login"
        }
    )
    [
        (assert-eq ($generic_only.bundle | get revad) $CERNBOX_REVAD_WEBAPP_SHARE
            "webapp-share revad by_flow default beats OCMTS_CERNBOX_REVAD_IMAGE")
        (assert-eq ($flow_revad.bundle | get revad) $custom_share_revad
            "OCMTS_CERNBOX_REVAD_WEBAPP_SHARE_IMAGE still overrides webapp-share revad")
        (assert-eq ($login.bundle | get revad) $custom_revad
            "OCMTS_CERNBOX_REVAD_IMAGE still overrides login revad")
        (assert-eq ($generic_only.bundle | get idp) $custom_idp
            "OCMTS_CERNBOX_IDP_IMAGE still overrides idp")
        (assert-eq ($generic_only.bundle | get registry) $CERNBOX_REGISTRY_DEFAULT
            "idp and revad overrides leave the registry slot on its default")
        (assert-eq ($login.bundle | get idp) $CERNBOX_IDP_DEFAULT
            "login idp default is unchanged when only revad env is set")
    ]
}

def test-nextcloud-v35-webapp-share-flow-default-beats-version-default [] {
    test-log "\n[test-nextcloud-v35-webapp-share-flow-default-beats-version-default]"
    let got = (
        with-env (leaked-platform-image-env-mask) {
            (resolve-images "nextcloud" "v35" --flow-id "webapp-share").platform
        }
    )
    [
        (assert-eq $got $NEXTCLOUD_V35_WEBAPP_SHARE_DEFAULT
            "webapp-share by_flow default wins over nextcloud/v35 version default")
    ]
}

def test-nextcloud-v35-webapp-share-sender-role-env [] {
    test-log "\n[test-nextcloud-v35-webapp-share-sender-role-env]"
    let sender_role = "localhost/ocmts/nextcloud-v35-webapp-share-sender:local"
    let got = (
        with-env (leaked-platform-image-env-mask | merge {
            OCMTS_NEXTCLOUD_V35_WEBAPP_SHARE_SENDER_IMAGE: $sender_role
        }) {
            (resolve-images "nextcloud" "v35" --flow-id "webapp-share").platform
        }
    )
    [
        (assert-eq $got $sender_role
            "OCMTS_NEXTCLOUD_V35_WEBAPP_SHARE_SENDER_IMAGE applies to sender platform ref")
    ]
}

def test-nextcloud-v35-webapp-share-receiver-role-env [] {
    test-log "\n[test-nextcloud-v35-webapp-share-receiver-role-env]"
    let receiver_role = "localhost/ocmts/nextcloud-v35-webapp-share-receiver:local"
    let got = (
        with-env (leaked-platform-image-env-mask | merge {
            OCMTS_NEXTCLOUD_V35_WEBAPP_SHARE_RECEIVER_IMAGE: $receiver_role
        }) {
            resolve-receiver-image "nextcloud" "v35" --flow-id "webapp-share"
        }
    )
    [
        (assert-eq $got $receiver_role
            "OCMTS_NEXTCLOUD_V35_WEBAPP_SHARE_RECEIVER_IMAGE applies to receiver ref")
    ]
}

def test-nextcloud-v35-webapp-share-flow-generic-env-beats-version-role-env [] {
    test-log "\n[test-nextcloud-v35-webapp-share-flow-generic-env-beats-version-role-env]"
    let flow_generic = "localhost/ocmts/nextcloud-v35-webapp-share:local"
    let version_role = "ghcr.io/example/nextcloud:version-sender-role"
    let got = (
        with-env (leaked-platform-image-env-mask | merge {
            OCMTS_NEXTCLOUD_V35_SENDER_IMAGE: $version_role
            OCMTS_NEXTCLOUD_V35_WEBAPP_SHARE_IMAGE: $flow_generic
        }) {
            (resolve-images "nextcloud" "v35" --flow-id "webapp-share").platform
        }
    )
    [
        (assert-eq $got $flow_generic
            "webapp-share flow-scoped generic override_env beats version-scoped sender role env")
    ]
}

def test-nextcloud-v35-webapp-share-sender-and-receiver-role-env-independence [] {
    test-log "\n[test-nextcloud-v35-webapp-share-sender-and-receiver-role-env-independence]"
    let sender_role = "localhost/ocmts/nextcloud-v35-webapp-share-sender:local"
    let receiver_role = "localhost/ocmts/nextcloud-v35-webapp-share-receiver:local"
    let got = (
        with-env (leaked-platform-image-env-mask | merge {
            OCMTS_NEXTCLOUD_V35_WEBAPP_SHARE_SENDER_IMAGE: $sender_role
            OCMTS_NEXTCLOUD_V35_WEBAPP_SHARE_RECEIVER_IMAGE: $receiver_role
        }) {
            {
                sender: ((resolve-images "nextcloud" "v35" --flow-id "webapp-share").platform)
                receiver: (resolve-receiver-image "nextcloud" "v35" --flow-id "webapp-share")
            }
        }
    )
    [
        (assert-eq $got.sender $sender_role
            "webapp-share sender role env does not affect receiver resolution")
        (assert-eq $got.receiver $receiver_role
            "webapp-share receiver role env does not affect sender resolution")
    ]
}

def main [] {
    test-log "=== images/resolve-role-overrides-webapp-share Tests ==="
    let results = (
        (test-cernbox-registry-generic-override-all-flows)
        | append (test-cernbox-revad-and-idp-override-semantics-unchanged)
        | append (test-nextcloud-v35-webapp-share-flow-default-beats-version-default)
        | append (test-nextcloud-v35-webapp-share-sender-role-env)
        | append (test-nextcloud-v35-webapp-share-receiver-role-env)
        | append (test-nextcloud-v35-webapp-share-flow-generic-env-beats-version-role-env)
        | append (test-nextcloud-v35-webapp-share-sender-and-receiver-role-env-independence)
    ) | flatten
    run-suite "images/resolve-role-overrides-webapp-share" $SUITE_PATH $results
}
