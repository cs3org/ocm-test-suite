# resolve-images / resolve-receiver-image role override runtime tests.
# Proves platform-level sender/receiver env keys beat generic override_env
# through the live resolver path (not just precedence.nu unit fixtures).
# Run: nu scripts/tests/images/resolve-role-overrides.nu

const SUITE_PATH = path self

use ../../lib/images/resolve.nu [resolve-images resolve-receiver-image]
use ../../lib/tests/assert.nu *
use ../../lib/tests/runner.nu [run-suite]

const OCMGO_DEFAULT = "ghcr.io/mahdibaghbani/containers/opencloudmesh-go:v1.0.0"
const NEXTCLOUD_DEFAULT = "ghcr.io/mahdibaghbani/containers/nextcloud:v32.0.9"
const OPENCLOUD_DEFAULT = "ghcr.io/mahdibaghbani/containers/opencloud:v6.1.0"
const OCIS_DEFAULT = "ghcr.io/mahdibaghbani/containers/ocis:v8.0.1"

def leaked-role-image-env-mask [] {
    [
        OCMTS_OCMGO_SENDER_IMAGE
        OCMTS_OCMGO_RECEIVER_IMAGE
        OCMTS_NEXTCLOUD_SENDER_IMAGE
        OCMTS_NEXTCLOUD_RECEIVER_IMAGE
        OCMTS_OPENCLOUD_SENDER_IMAGE
        OCMTS_OPENCLOUD_RECEIVER_IMAGE
        OCMTS_OCIS_SENDER_IMAGE
        OCMTS_OCIS_RECEIVER_IMAGE
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
                OCMTS_OCMGO_IMAGE
                OCMTS_NEXTCLOUD_IMAGE
                OCMTS_OPENCLOUD_IMAGE
                OCMTS_OCIS_IMAGE
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
        with-env {
            OCMTS_OCMGO_IMAGE: $generic
            OCMTS_OCMGO_SENDER_IMAGE: $role
        } {
            (resolve-images "ocmgo" "v1").platform
        }
    )
    [
        (assert-eq $got $role
            "OCMTS_OCMGO_SENDER_IMAGE beats OCMTS_OCMGO_IMAGE for sender platform ref")
    ]
}

def test-receiver-role-env-beats-generic-platform-env [] {
    test-log "\n[test-receiver-role-env-beats-generic-platform-env]"
    let generic = "ghcr.io/example/nextcloud:generic"
    let role = "ghcr.io/example/nextcloud:receiver-role"
    let got = (
        with-env {
            OCMTS_NEXTCLOUD_IMAGE: $generic
            OCMTS_NEXTCLOUD_RECEIVER_IMAGE: $role
        } {
            resolve-receiver-image "nextcloud" "v32"
        }
    )
    [
        (assert-eq $got $role
            "OCMTS_NEXTCLOUD_RECEIVER_IMAGE beats OCMTS_NEXTCLOUD_IMAGE for receiver ref")
    ]
}

def test-sender-falls-back-to-generic-when-role-env-unset [] {
    test-log "\n[test-sender-falls-back-to-generic-when-role-env-unset]"
    let generic = "ghcr.io/example/ocmgo:generic-only"
    let got = (
        with-env (leaked-role-image-env-mask | merge { OCMTS_OCMGO_IMAGE: $generic }) {
            (resolve-images "ocmgo" "v1").platform
        }
    )
    [
        (assert-eq $got $generic
            "OCMTS_OCMGO_IMAGE applies when sender role env is unset")
    ]
}

def test-receiver-falls-back-to-generic-when-role-env-unset [] {
    test-log "\n[test-receiver-falls-back-to-generic-when-role-env-unset]"
    let generic = "ghcr.io/example/nextcloud:generic-only"
    let got = (
        with-env (leaked-role-image-env-mask | merge { OCMTS_NEXTCLOUD_IMAGE: $generic }) {
            resolve-receiver-image "nextcloud" "v32"
        }
    )
    [
        (assert-eq $got $generic
            "OCMTS_NEXTCLOUD_IMAGE applies when receiver role env is unset")
    ]
}

def test-sender-falls-back-to-generic-when-role-env-empty-string [] {
    test-log "\n[test-sender-falls-back-to-generic-when-role-env-empty-string]"
    let generic = "ghcr.io/example/ocmgo:generic-empty-role"
    let got = (
        with-env (
            leaked-role-image-env-mask
            | merge {
                OCMTS_OCMGO_IMAGE: $generic
                OCMTS_OCMGO_SENDER_IMAGE: ""
            }
        ) {
            (resolve-images "ocmgo" "v1").platform
        }
    )
    [
        (assert-eq $got $generic
            "OCMTS_OCMGO_IMAGE applies when sender role env is empty string")
    ]
}

def test-receiver-falls-back-to-generic-when-role-env-empty-string [] {
    test-log "\n[test-receiver-falls-back-to-generic-when-role-env-empty-string]"
    let generic = "ghcr.io/example/nextcloud:generic-empty-role"
    let got = (
        with-env (
            leaked-role-image-env-mask
            | merge {
                OCMTS_NEXTCLOUD_IMAGE: $generic
                OCMTS_NEXTCLOUD_RECEIVER_IMAGE: ""
            }
        ) {
            resolve-receiver-image "nextcloud" "v32"
        }
    )
    [
        (assert-eq $got $generic
            "OCMTS_NEXTCLOUD_IMAGE applies when receiver role env is empty string")
    ]
}

def test-sender-ignores-receiver-role-env [] {
    test-log "\n[test-sender-ignores-receiver-role-env]"
    let sender_role = "ghcr.io/example/ocmgo:sender-only"
    let bogus_receiver = "ghcr.io/example/ocmgo:receiver-leak"
    let got = (
        with-env (
            leaked-role-image-env-mask
            | merge {
                OCMTS_OCMGO_SENDER_IMAGE: $sender_role
                OCMTS_OCMGO_RECEIVER_IMAGE: $bogus_receiver
            }
        ) {
            (resolve-images "ocmgo" "v1").platform
        }
    )
    [
        (assert-eq $got $sender_role
            "sender resolution ignores OCMTS_OCMGO_RECEIVER_IMAGE")
    ]
}

def test-receiver-ignores-sender-role-env [] {
    test-log "\n[test-receiver-ignores-sender-role-env]"
    let receiver_role = "ghcr.io/example/nextcloud:receiver-only"
    let bogus_sender = "ghcr.io/example/nextcloud:sender-leak"
    let got = (
        with-env (
            leaked-role-image-env-mask
            | merge {
                OCMTS_NEXTCLOUD_SENDER_IMAGE: $bogus_sender
                OCMTS_NEXTCLOUD_RECEIVER_IMAGE: $receiver_role
            }
        ) {
            resolve-receiver-image "nextcloud" "v32"
        }
    )
    [
        (assert-eq $got $receiver_role
            "receiver resolution ignores OCMTS_NEXTCLOUD_SENDER_IMAGE")
    ]
}

def test-opencloud-sender-role-env-beats-generic-platform-env [] {
    test-log "\n[test-opencloud-sender-role-env-beats-generic-platform-env]"
    let generic = "ghcr.io/example/opencloud:generic"
    let role = "ghcr.io/example/opencloud:sender-role"
    let got = (
        with-env {
            OCMTS_OPENCLOUD_IMAGE: $generic
            OCMTS_OPENCLOUD_SENDER_IMAGE: $role
        } {
            (resolve-images "opencloud" "v6").platform
        }
    )
    [
        (assert-eq $got $role
            "OCMTS_OPENCLOUD_SENDER_IMAGE beats OCMTS_OPENCLOUD_IMAGE for sender platform ref")
    ]
}

def test-ocis-receiver-role-env-beats-generic-platform-env [] {
    test-log "\n[test-ocis-receiver-role-env-beats-generic-platform-env]"
    let generic = "ghcr.io/example/ocis:generic"
    let role = "ghcr.io/example/ocis:receiver-role"
    let got = (
        with-env {
            OCMTS_OCIS_IMAGE: $generic
            OCMTS_OCIS_RECEIVER_IMAGE: $role
        } {
            resolve-receiver-image "ocis" "v8"
        }
    )
    [
        (assert-eq $got $role
            "OCMTS_OCIS_RECEIVER_IMAGE beats OCMTS_OCIS_IMAGE for receiver ref")
    ]
}

def test-opencloud-sender-falls-back-to-generic-when-role-env-unset [] {
    test-log "\n[test-opencloud-sender-falls-back-to-generic-when-role-env-unset]"
    let generic = "ghcr.io/example/opencloud:generic-only"
    let got = (
        with-env (leaked-role-image-env-mask | merge { OCMTS_OPENCLOUD_IMAGE: $generic }) {
            (resolve-images "opencloud" "v6").platform
        }
    )
    [
        (assert-eq $got $generic
            "OCMTS_OPENCLOUD_IMAGE applies when sender role env is unset")
    ]
}

def test-ocis-receiver-falls-back-to-generic-when-role-env-unset [] {
    test-log "\n[test-ocis-receiver-falls-back-to-generic-when-role-env-unset]"
    let generic = "ghcr.io/example/ocis:generic-only"
    let got = (
        with-env (leaked-role-image-env-mask | merge { OCMTS_OCIS_IMAGE: $generic }) {
            resolve-receiver-image "ocis" "v8"
        }
    )
    [
        (assert-eq $got $generic
            "OCMTS_OCIS_IMAGE applies when receiver role env is unset")
    ]
}

def test-opencloud-sender-falls-back-to-generic-when-role-env-empty-string [] {
    test-log "\n[test-opencloud-sender-falls-back-to-generic-when-role-env-empty-string]"
    let generic = "ghcr.io/example/opencloud:generic-empty-role"
    let got = (
        with-env (
            leaked-role-image-env-mask
            | merge {
                OCMTS_OPENCLOUD_IMAGE: $generic
                OCMTS_OPENCLOUD_SENDER_IMAGE: ""
            }
        ) {
            (resolve-images "opencloud" "v6").platform
        }
    )
    [
        (assert-eq $got $generic
            "OCMTS_OPENCLOUD_IMAGE applies when sender role env is empty string")
    ]
}

def test-ocis-receiver-falls-back-to-generic-when-role-env-empty-string [] {
    test-log "\n[test-ocis-receiver-falls-back-to-generic-when-role-env-empty-string]"
    let generic = "ghcr.io/example/ocis:generic-empty-role"
    let got = (
        with-env (
            leaked-role-image-env-mask
            | merge {
                OCMTS_OCIS_IMAGE: $generic
                OCMTS_OCIS_RECEIVER_IMAGE: ""
            }
        ) {
            resolve-receiver-image "ocis" "v8"
        }
    )
    [
        (assert-eq $got $generic
            "OCMTS_OCIS_IMAGE applies when receiver role env is empty string")
    ]
}

def test-opencloud-sender-ignores-receiver-role-env [] {
    test-log "\n[test-opencloud-sender-ignores-receiver-role-env]"
    let sender_role = "ghcr.io/example/opencloud:sender-only"
    let bogus_receiver = "ghcr.io/example/opencloud:receiver-leak"
    let got = (
        with-env (
            leaked-role-image-env-mask
            | merge {
                OCMTS_OPENCLOUD_SENDER_IMAGE: $sender_role
                OCMTS_OPENCLOUD_RECEIVER_IMAGE: $bogus_receiver
            }
        ) {
            (resolve-images "opencloud" "v6").platform
        }
    )
    [
        (assert-eq $got $sender_role
            "opencloud sender resolution ignores OCMTS_OPENCLOUD_RECEIVER_IMAGE")
    ]
}

def test-ocis-receiver-ignores-sender-role-env [] {
    test-log "\n[test-ocis-receiver-ignores-sender-role-env]"
    let receiver_role = "ghcr.io/example/ocis:receiver-only"
    let bogus_sender = "ghcr.io/example/ocis:sender-leak"
    let got = (
        with-env (
            leaked-role-image-env-mask
            | merge {
                OCMTS_OCIS_SENDER_IMAGE: $bogus_sender
                OCMTS_OCIS_RECEIVER_IMAGE: $receiver_role
            }
        ) {
            resolve-receiver-image "ocis" "v8"
        }
    )
    [
        (assert-eq $got $receiver_role
            "ocis receiver resolution ignores OCMTS_OCIS_SENDER_IMAGE")
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
        (assert-eq $sender_receiver.ocmgo_sender $OCMGO_DEFAULT
            "ocmgo/v1 sender default unchanged")
        (assert-eq $sender_receiver.nextcloud_receiver $NEXTCLOUD_DEFAULT
            "nextcloud/v32 receiver default unchanged")
        (assert-eq $sender_receiver.opencloud_sender $OPENCLOUD_DEFAULT
            "opencloud/v6 sender default unchanged")
        (assert-eq $sender_receiver.ocis_receiver $OCIS_DEFAULT
            "ocis/v8 receiver default unchanged")
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
        | append (test-opencloud-sender-falls-back-to-generic-when-role-env-unset)
        | append (test-ocis-receiver-falls-back-to-generic-when-role-env-unset)
        | append (test-opencloud-sender-falls-back-to-generic-when-role-env-empty-string)
        | append (test-ocis-receiver-falls-back-to-generic-when-role-env-empty-string)
        | append (test-opencloud-sender-ignores-receiver-role-env)
        | append (test-ocis-receiver-ignores-sender-role-env)
        | append (test-defaults-when-no-env-set)
    ) | flatten
    run-suite "images/resolve-role-overrides" $SUITE_PATH $results
}
