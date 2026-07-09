# resolve-images / resolve-receiver-image webapp-share flow override tests.
# Proves nextcloud/v35 webapp-share by_flow scope wins over version scope for
# defaults, role env, and generic flow env vs version role env.
# Run: nu scripts/tests/images/resolve-role-overrides-webapp-share.nu

const SUITE_PATH = path self

use ../../lib/images/resolve.nu [resolve-images resolve-receiver-image]
use ../../lib/tests/assert.nu *
use ../../lib/tests/runner.nu [run-suite]

const NEXTCLOUD_V35_WEBAPP_SHARE_DEFAULT = "ghcr.io/mahdibaghbani/containers/nextcloud-webapp:webapp-share"

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
        (test-nextcloud-v35-webapp-share-flow-default-beats-version-default)
        | append (test-nextcloud-v35-webapp-share-sender-role-env)
        | append (test-nextcloud-v35-webapp-share-receiver-role-env)
        | append (test-nextcloud-v35-webapp-share-flow-generic-env-beats-version-role-env)
        | append (test-nextcloud-v35-webapp-share-sender-and-receiver-role-env-independence)
    ) | flatten
    run-suite "images/resolve-role-overrides-webapp-share" $SUITE_PATH $results
}
