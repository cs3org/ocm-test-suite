# resolve-images / resolve-receiver-image role override runtime tests.
# Proves version-scoped and flow-scoped sender/receiver override_env keys beat
# generic override_env through the live resolver path against real
# config/images.nuon (not just precedence.nu unit fixtures). by_flow scope
# wins over version scope for nextcloud/v35 contact-token and contact-wayf.
# Run: nu scripts/tests/images/resolve-role-overrides.nu

const SUITE_PATH = path self

use ../../lib/images/resolve.nu [resolve-images resolve-receiver-image]
use ../../lib/tests/assert.nu *
use ../../lib/tests/runner.nu [run-suite]

const OCMGO_V1_DEFAULT = "ghcr.io/mahdibaghbani/containers/opencloudmesh-go:v1.1.0"
const NEXTCLOUD_V32_DEFAULT = "ghcr.io/mahdibaghbani/containers/nextcloud:v32.0.12"
const OPENCLOUD_V6_DEFAULT = "ghcr.io/mahdibaghbani/containers/opencloud:v6.1.0"
const OCIS_V8_DEFAULT = "ghcr.io/mahdibaghbani/containers/ocis:v8.0.1"
const NEXTCLOUD_V34_DEFAULT = "ghcr.io/mahdibaghbani/containers/nextcloud:v34.0.1"
const NEXTCLOUD_CONTACTS_DEFAULT = "ghcr.io/mahdibaghbani/containers/nextcloud-contacts:ocm-contacts-app"

def leaked-role-image-env-mask [] {
    [
        OCMTS_OCMGO_V1_SENDER_IMAGE
        OCMTS_OCMGO_V1_RECEIVER_IMAGE
        OCMTS_NEXTCLOUD_V32_SENDER_IMAGE
        OCMTS_NEXTCLOUD_V32_RECEIVER_IMAGE
        OCMTS_OPENCLOUD_V6_SENDER_IMAGE
        OCMTS_OPENCLOUD_V6_RECEIVER_IMAGE
        OCMTS_OCIS_V8_SENDER_IMAGE
        OCMTS_OCIS_V8_RECEIVER_IMAGE
        OCMTS_NEXTCLOUD_V34_SENDER_IMAGE
        OCMTS_NEXTCLOUD_V34_RECEIVER_IMAGE
        OCMTS_NEXTCLOUD_V35_SENDER_IMAGE
        OCMTS_NEXTCLOUD_V35_RECEIVER_IMAGE
        OCMTS_NEXTCLOUD_V35_CONTACT_TOKEN_SENDER_IMAGE
        OCMTS_NEXTCLOUD_V35_CONTACT_TOKEN_RECEIVER_IMAGE
        OCMTS_NEXTCLOUD_V35_CONTACT_WAYF_SENDER_IMAGE
        OCMTS_NEXTCLOUD_V35_CONTACT_WAYF_RECEIVER_IMAGE
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
                OCMTS_OCMGO_V1_IMAGE
                OCMTS_NEXTCLOUD_V32_IMAGE
                OCMTS_OPENCLOUD_V6_IMAGE
                OCMTS_OCIS_V8_IMAGE
                OCMTS_NEXTCLOUD_V34_IMAGE
                OCMTS_NEXTCLOUD_V35_IMAGE
                OCMTS_NEXTCLOUD_V35_CONTACT_TOKEN_IMAGE
                OCMTS_NEXTCLOUD_V35_CONTACT_WAYF_IMAGE
            ]
            | reduce --fold {} {|k, acc|
                if $k in $env { $acc | upsert $k null } else { $acc }
            }
        )
    )
}

def test-sender-role-env-beats-generic-platform-env [] {
    test-log "\n[test-sender-role-env-beats-generic-platform-env]"
    let generic = "ghcr.io/example/ocmgo:generic"
    let role = "ghcr.io/example/ocmgo:sender-role"
    let got = (
        with-env (leaked-platform-image-env-mask | merge {
            OCMTS_OCMGO_V1_IMAGE: $generic
            OCMTS_OCMGO_V1_SENDER_IMAGE: $role
        }) {
            (resolve-images "ocmgo" "v1").platform
        }
    )
    [
        (assert-eq $got $role
            "OCMTS_OCMGO_V1_SENDER_IMAGE beats OCMTS_OCMGO_V1_IMAGE for sender platform ref")
    ]
}

def test-receiver-role-env-beats-generic-platform-env [] {
    test-log "\n[test-receiver-role-env-beats-generic-platform-env]"
    let generic = "ghcr.io/example/nextcloud:generic"
    let role = "ghcr.io/example/nextcloud:receiver-role"
    let got = (
        with-env (leaked-platform-image-env-mask | merge {
            OCMTS_NEXTCLOUD_V32_IMAGE: $generic
            OCMTS_NEXTCLOUD_V32_RECEIVER_IMAGE: $role
        }) {
            resolve-receiver-image "nextcloud" "v32"
        }
    )
    [
        (assert-eq $got $role
            "OCMTS_NEXTCLOUD_V32_RECEIVER_IMAGE beats OCMTS_NEXTCLOUD_V32_IMAGE for receiver ref")
    ]
}

def test-sender-falls-back-to-generic-when-role-env-unset [] {
    test-log "\n[test-sender-falls-back-to-generic-when-role-env-unset]"
    let generic = "ghcr.io/example/ocmgo:generic-only"
    let got = (
        with-env (leaked-platform-image-env-mask | merge { OCMTS_OCMGO_V1_IMAGE: $generic }) {
            (resolve-images "ocmgo" "v1").platform
        }
    )
    [
        (assert-eq $got $generic
            "OCMTS_OCMGO_V1_IMAGE applies when sender role env is unset")
    ]
}

def test-receiver-falls-back-to-generic-when-role-env-unset [] {
    test-log "\n[test-receiver-falls-back-to-generic-when-role-env-unset]"
    let generic = "ghcr.io/example/nextcloud:generic-only"
    let got = (
        with-env (leaked-platform-image-env-mask | merge { OCMTS_NEXTCLOUD_V32_IMAGE: $generic }) {
            resolve-receiver-image "nextcloud" "v32"
        }
    )
    [
        (assert-eq $got $generic
            "OCMTS_NEXTCLOUD_V32_IMAGE applies when receiver role env is unset")
    ]
}

def test-sender-falls-back-to-generic-when-role-env-empty-string [] {
    test-log "\n[test-sender-falls-back-to-generic-when-role-env-empty-string]"
    let generic = "ghcr.io/example/ocmgo:generic-empty-role"
    let got = (
        with-env (
            leaked-platform-image-env-mask
            | merge {
                OCMTS_OCMGO_V1_IMAGE: $generic
                OCMTS_OCMGO_V1_SENDER_IMAGE: ""
            }
        ) {
            (resolve-images "ocmgo" "v1").platform
        }
    )
    [
        (assert-eq $got $generic
            "OCMTS_OCMGO_V1_IMAGE applies when sender role env is empty string")
    ]
}

def test-receiver-falls-back-to-generic-when-role-env-empty-string [] {
    test-log "\n[test-receiver-falls-back-to-generic-when-role-env-empty-string]"
    let generic = "ghcr.io/example/nextcloud:generic-empty-role"
    let got = (
        with-env (
            leaked-platform-image-env-mask
            | merge {
                OCMTS_NEXTCLOUD_V32_IMAGE: $generic
                OCMTS_NEXTCLOUD_V32_RECEIVER_IMAGE: ""
            }
        ) {
            resolve-receiver-image "nextcloud" "v32"
        }
    )
    [
        (assert-eq $got $generic
            "OCMTS_NEXTCLOUD_V32_IMAGE applies when receiver role env is empty string")
    ]
}

def test-sender-ignores-receiver-role-env [] {
    test-log "\n[test-sender-ignores-receiver-role-env]"
    let sender_role = "ghcr.io/example/ocmgo:sender-only"
    let bogus_receiver = "ghcr.io/example/ocmgo:receiver-leak"
    let got = (
        with-env (
            leaked-platform-image-env-mask
            | merge {
                OCMTS_OCMGO_V1_SENDER_IMAGE: $sender_role
                OCMTS_OCMGO_V1_RECEIVER_IMAGE: $bogus_receiver
            }
        ) {
            (resolve-images "ocmgo" "v1").platform
        }
    )
    [
        (assert-eq $got $sender_role
            "sender resolution ignores OCMTS_OCMGO_V1_RECEIVER_IMAGE")
    ]
}

def test-receiver-ignores-sender-role-env [] {
    test-log "\n[test-receiver-ignores-sender-role-env]"
    let receiver_role = "ghcr.io/example/nextcloud:receiver-only"
    let bogus_sender = "ghcr.io/example/nextcloud:sender-leak"
    let got = (
        with-env (
            leaked-platform-image-env-mask
            | merge {
                OCMTS_NEXTCLOUD_V32_SENDER_IMAGE: $bogus_sender
                OCMTS_NEXTCLOUD_V32_RECEIVER_IMAGE: $receiver_role
            }
        ) {
            resolve-receiver-image "nextcloud" "v32"
        }
    )
    [
        (assert-eq $got $receiver_role
            "receiver resolution ignores OCMTS_NEXTCLOUD_V32_SENDER_IMAGE")
    ]
}

def test-opencloud-sender-role-env-beats-generic-platform-env [] {
    test-log "\n[test-opencloud-sender-role-env-beats-generic-platform-env]"
    let generic = "ghcr.io/example/opencloud:generic"
    let role = "ghcr.io/example/opencloud:sender-role"
    let got = (
        with-env (leaked-platform-image-env-mask | merge {
            OCMTS_OPENCLOUD_V6_IMAGE: $generic
            OCMTS_OPENCLOUD_V6_SENDER_IMAGE: $role
        }) {
            (resolve-images "opencloud" "v6").platform
        }
    )
    [
        (assert-eq $got $role
            "OCMTS_OPENCLOUD_V6_SENDER_IMAGE beats OCMTS_OPENCLOUD_V6_IMAGE for sender platform ref")
    ]
}

def test-ocis-receiver-role-env-beats-generic-platform-env [] {
    test-log "\n[test-ocis-receiver-role-env-beats-generic-platform-env]"
    let generic = "ghcr.io/example/ocis:generic"
    let role = "ghcr.io/example/ocis:receiver-role"
    let got = (
        with-env (leaked-platform-image-env-mask | merge {
            OCMTS_OCIS_V8_IMAGE: $generic
            OCMTS_OCIS_V8_RECEIVER_IMAGE: $role
        }) {
            resolve-receiver-image "ocis" "v8"
        }
    )
    [
        (assert-eq $got $role
            "OCMTS_OCIS_V8_RECEIVER_IMAGE beats OCMTS_OCIS_V8_IMAGE for receiver ref")
    ]
}

def test-defaults-when-no-env-set [] {
    test-log "\n[test-defaults-when-no-env-set]"
    let sender_receiver = (
        with-env (leaked-platform-image-env-mask) {
            {
                ocmgo_sender: ((resolve-images "ocmgo" "v1").platform)
                nextcloud_receiver: (resolve-receiver-image "nextcloud" "v32")
                opencloud_sender: ((resolve-images "opencloud" "v6").platform)
                ocis_receiver: (resolve-receiver-image "ocis" "v8")
            }
        }
    )
    [
        (assert-eq $sender_receiver.ocmgo_sender $OCMGO_V1_DEFAULT
            "ocmgo/v1 sender default unchanged")
        (assert-eq $sender_receiver.nextcloud_receiver $NEXTCLOUD_V32_DEFAULT
            "nextcloud/v32 receiver default unchanged")
        (assert-eq $sender_receiver.opencloud_sender $OPENCLOUD_V6_DEFAULT
            "opencloud/v6 sender default unchanged")
        (assert-eq $sender_receiver.ocis_receiver $OCIS_V8_DEFAULT
            "ocis/v8 receiver default unchanged")
    ]
}

# ---- real-config integration: nextcloud/v35 by_flow contact flows ----
# by_flow scope must win over version scope, and win regardless of kind
# (a flow-scoped generic override_env beats a version-scoped role env).

def test-nextcloud-v35-contact-token-flow-default-beats-version-default [] {
    test-log "\n[test-nextcloud-v35-contact-token-flow-default-beats-version-default]"
    let got = (
        with-env (leaked-platform-image-env-mask) {
            (resolve-images "nextcloud" "v35" --flow-id "contact-token").platform
        }
    )
    [
        (assert-eq $got $NEXTCLOUD_CONTACTS_DEFAULT
            "contact-token by_flow default wins over nextcloud/v35 version default")
    ]
}

def test-nextcloud-v35-contact-wayf-flow-default-beats-version-default [] {
    test-log "\n[test-nextcloud-v35-contact-wayf-flow-default-beats-version-default]"
    let got = (
        with-env (leaked-platform-image-env-mask) {
            (resolve-images "nextcloud" "v35" --flow-id "contact-wayf").platform
        }
    )
    [
        (assert-eq $got $NEXTCLOUD_CONTACTS_DEFAULT
            "contact-wayf by_flow default wins over nextcloud/v35 version default")
    ]
}

def test-nextcloud-v35-contact-token-flow-role-env-beats-version-role-env [] {
    test-log "\n[test-nextcloud-v35-contact-token-flow-role-env-beats-version-role-env]"
    let flow_role = "ghcr.io/example/nextcloud-contacts:flow-sender-role"
    let version_role = "ghcr.io/example/nextcloud:version-sender-role"
    let got = (
        with-env (leaked-platform-image-env-mask | merge {
            OCMTS_NEXTCLOUD_V35_SENDER_IMAGE: $version_role
            OCMTS_NEXTCLOUD_V35_CONTACT_TOKEN_SENDER_IMAGE: $flow_role
        }) {
            (resolve-images "nextcloud" "v35" --flow-id "contact-token").platform
        }
    )
    [
        (assert-eq $got $flow_role
            "flow-scoped sender_override_env beats version-scoped sender_override_env")
    ]
}

def test-nextcloud-v35-contact-token-flow-generic-env-beats-version-role-env [] {
    test-log "\n[test-nextcloud-v35-contact-token-flow-generic-env-beats-version-role-env]"
    let flow_generic = "ghcr.io/example/nextcloud-contacts:flow-generic"
    let version_role = "ghcr.io/example/nextcloud:version-sender-role"
    let got = (
        with-env (leaked-platform-image-env-mask | merge {
            OCMTS_NEXTCLOUD_V35_SENDER_IMAGE: $version_role
            OCMTS_NEXTCLOUD_V35_CONTACT_TOKEN_IMAGE: $flow_generic
        }) {
            (resolve-images "nextcloud" "v35" --flow-id "contact-token").platform
        }
    )
    [
        (assert-eq $got $flow_generic
            "flow-scoped generic override_env beats version-scoped role env: scope wins before kind")
    ]
}

def test-nextcloud-v35-contact-token-receiver-flow-role-env [] {
    test-log "\n[test-nextcloud-v35-contact-token-receiver-flow-role-env]"
    let receiver_role = "ghcr.io/example/nextcloud-contacts:flow-receiver-role"
    let got = (
        with-env (leaked-platform-image-env-mask | merge {
            OCMTS_NEXTCLOUD_V35_CONTACT_TOKEN_RECEIVER_IMAGE: $receiver_role
        }) {
            resolve-receiver-image "nextcloud" "v35" --flow-id "contact-token"
        }
    )
    [
        (assert-eq $got $receiver_role
            "contact-token by_flow receiver_override_env applies to receiver resolution")
    ]
}

def test-nextcloud-v35-contact-wayf-flow-role-env-beats-version-role-env [] {
    test-log "\n[test-nextcloud-v35-contact-wayf-flow-role-env-beats-version-role-env]"
    let flow_role = "ghcr.io/example/nextcloud-contacts:wayf-flow-sender-role"
    let version_role = "ghcr.io/example/nextcloud:version-sender-role"
    let got = (
        with-env (leaked-platform-image-env-mask | merge {
            OCMTS_NEXTCLOUD_V35_SENDER_IMAGE: $version_role
            OCMTS_NEXTCLOUD_V35_CONTACT_WAYF_SENDER_IMAGE: $flow_role
        }) {
            (resolve-images "nextcloud" "v35" --flow-id "contact-wayf").platform
        }
    )
    [
        (assert-eq $got $flow_role
            "contact-wayf flow-scoped sender_override_env beats version-scoped sender_override_env")
    ]
}

def test-nextcloud-v35-contact-wayf-flow-generic-env-beats-version-role-env [] {
    test-log "\n[test-nextcloud-v35-contact-wayf-flow-generic-env-beats-version-role-env]"
    let flow_generic = "ghcr.io/example/nextcloud-contacts:wayf-flow-generic"
    let version_role = "ghcr.io/example/nextcloud:version-sender-role"
    let got = (
        with-env (leaked-platform-image-env-mask | merge {
            OCMTS_NEXTCLOUD_V35_SENDER_IMAGE: $version_role
            OCMTS_NEXTCLOUD_V35_CONTACT_WAYF_IMAGE: $flow_generic
        }) {
            (resolve-images "nextcloud" "v35" --flow-id "contact-wayf").platform
        }
    )
    [
        (assert-eq $got $flow_generic
            "contact-wayf flow-scoped generic override_env beats version-scoped role env: scope wins before kind")
    ]
}

def test-nextcloud-v35-contact-wayf-receiver-flow-role-env [] {
    test-log "\n[test-nextcloud-v35-contact-wayf-receiver-flow-role-env]"
    let receiver_role = "ghcr.io/example/nextcloud-contacts:wayf-receiver-role"
    let got = (
        with-env (leaked-platform-image-env-mask | merge {
            OCMTS_NEXTCLOUD_V35_CONTACT_WAYF_RECEIVER_IMAGE: $receiver_role
        }) {
            resolve-receiver-image "nextcloud" "v35" --flow-id "contact-wayf"
        }
    )
    [
        (assert-eq $got $receiver_role
            "contact-wayf by_flow receiver_override_env applies to receiver resolution")
    ]
}

def test-nextcloud-v34-non-contact-flow-ignores-contact-overrides [] {
    test-log "\n[test-nextcloud-v34-non-contact-flow-ignores-contact-overrides]"
    let got = (
        with-env (leaked-platform-image-env-mask | merge {
            OCMTS_NEXTCLOUD_V35_CONTACT_TOKEN_IMAGE: "ghcr.io/example/nextcloud-contacts:should-not-apply"
            OCMTS_NEXTCLOUD_V35_CONTACT_WAYF_IMAGE: "ghcr.io/example/nextcloud-contacts:should-not-apply"
        }) {
            (resolve-images "nextcloud" "v34" --flow-id "login").platform
        }
    )
    [
        (assert-eq $got $NEXTCLOUD_V34_DEFAULT
            "a flow_id outside by_flow ignores contact-token/contact-wayf overrides and uses version default")
    ]
}

def main [] {
    test-log "=== images/resolve-role-overrides Tests ==="
    let results = (
        (test-sender-role-env-beats-generic-platform-env)
        | append (test-receiver-role-env-beats-generic-platform-env)
        | append (test-sender-falls-back-to-generic-when-role-env-unset)
        | append (test-receiver-falls-back-to-generic-when-role-env-unset)
        | append (test-sender-falls-back-to-generic-when-role-env-empty-string)
        | append (test-receiver-falls-back-to-generic-when-role-env-empty-string)
        | append (test-sender-ignores-receiver-role-env)
        | append (test-receiver-ignores-sender-role-env)
        | append (test-opencloud-sender-role-env-beats-generic-platform-env)
        | append (test-ocis-receiver-role-env-beats-generic-platform-env)
        | append (test-defaults-when-no-env-set)
        | append (test-nextcloud-v35-contact-token-flow-default-beats-version-default)
        | append (test-nextcloud-v35-contact-wayf-flow-default-beats-version-default)
        | append (test-nextcloud-v35-contact-token-flow-role-env-beats-version-role-env)
        | append (test-nextcloud-v35-contact-token-flow-generic-env-beats-version-role-env)
        | append (test-nextcloud-v35-contact-token-receiver-flow-role-env)
        | append (test-nextcloud-v35-contact-wayf-flow-role-env-beats-version-role-env)
        | append (test-nextcloud-v35-contact-wayf-flow-generic-env-beats-version-role-env)
        | append (test-nextcloud-v35-contact-wayf-receiver-flow-role-env)
        | append (test-nextcloud-v34-non-contact-flow-ignores-contact-overrides)
    ) | flatten
    run-suite "images/resolve-role-overrides" $SUITE_PATH $results
}
