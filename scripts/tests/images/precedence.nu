# Image precedence unit tests.
# Run: nu scripts/tests/images/precedence.nu

const SUITE_PATH = path self

use ../../lib/images/precedence.nu [resolve-image resolve-platform-image]
use ../../lib/tests/assert.nu *
use ../../lib/tests/runner.nu [run-suite]

def test-resolve-platform-image-matrix-role-env-wins [] {
    test-log "\n[test-resolve-platform-image-matrix-role-env-wins]"
    let got = (with-env {
        OCMTS_MATRIX_ROLE_IMAGE: "ghcr.io/example/matrix-role:latest"
        OCMTS_FLOW_ROLE_IMAGE: "ghcr.io/example/flow-role:latest"
        OCMTS_VERSION_ROLE_IMAGE: "ghcr.io/example/version-role:latest"
        OCMTS_PLATFORM_ROLE_IMAGE: "ghcr.io/example/platform-role:latest"
        OCMTS_MATRIX_GENERIC_IMAGE: "ghcr.io/example/matrix-generic:latest"
        OCMTS_FLOW_GENERIC_IMAGE: "ghcr.io/example/flow-generic:latest"
        OCMTS_VERSION_GENERIC_IMAGE: "ghcr.io/example/version-generic:latest"
        OCMTS_PLATFORM_GENERIC_IMAGE: "ghcr.io/example/platform-generic:latest"
    } {
        (resolve-platform-image
            {
                sender_override_env: "OCMTS_PLATFORM_ROLE_IMAGE"
                override_env: "OCMTS_PLATFORM_GENERIC_IMAGE"
                default: "ghcr.io/example/platform-default:latest"
            }
            {
                sender_override_env: "OCMTS_VERSION_ROLE_IMAGE"
                override_env: "OCMTS_VERSION_GENERIC_IMAGE"
                default: "ghcr.io/example/version-default:latest"
                by_scenario: {
                    "share-with__nextcloud__ocmgo": {
                        sender_override_env: "OCMTS_MATRIX_ROLE_IMAGE"
                        override_env: "OCMTS_MATRIX_GENERIC_IMAGE"
                        default: "ghcr.io/example/matrix-default:latest"
                    }
                }
                by_flow: {
                    "share-with": {
                        sender_override_env: "OCMTS_FLOW_ROLE_IMAGE"
                        override_env: "OCMTS_FLOW_GENERIC_IMAGE"
                        default: "ghcr.io/example/flow-default:latest"
                    }
                }
            }
            "sender"
            "share-with__nextcloud__ocmgo"
            "share-with"
        )
    })
    [
        (assert-eq $got "ghcr.io/example/matrix-role:latest"
            "matrix-key sender_override_env beats by_flow, version, platform, and defaults")
    ]
}

def test-resolve-platform-image-matrix-default-wins-over-flow-default [] {
    test-log "\n[test-resolve-platform-image-matrix-default-wins-over-flow-default]"
    let got = (
        (resolve-platform-image
            {
                default: "ghcr.io/example/platform-default:latest"
            }
            {
                default: "ghcr.io/example/version-default:latest"
                by_scenario: {
                    "share-with__nextcloud__ocmgo": {
                        default: "ghcr.io/example/matrix-default:latest"
                    }
                }
                by_flow: {
                    "share-with": {
                        default: "ghcr.io/example/flow-default:latest"
                    }
                }
            }
            "sender"
            "share-with__nextcloud__ocmgo"
            "share-with"
        )
    )
    [
        (assert-eq $got "ghcr.io/example/matrix-default:latest"
            "matrix-key default beats by_flow default and version default")
    ]
}

def test-resolve-image-matrix-default-wins-over-flow-default [] {
    test-log "\n[test-resolve-image-matrix-default-wins-over-flow-default]"
    let got = (
        (resolve-image
            {
                default: "ghcr.io/example/root-default:latest"
                by_scenario: {
                    "share-with__nextcloud__ocmgo": {
                        default: "ghcr.io/example/matrix-default:latest"
                    }
                }
                by_flow: {
                    "share-with": {
                        default: "ghcr.io/example/flow-default:latest"
                    }
                }
            }
            "share-with__nextcloud__ocmgo"
            "share-with"
        )
    )
    [
        (assert-eq $got "ghcr.io/example/matrix-default:latest"
            "resolve-image prefers matrix-key default over by_flow and root defaults")
    ]
}

def test-resolve-platform-image-receiver-matrix-role-env-wins [] {
    test-log "\n[test-resolve-platform-image-receiver-matrix-role-env-wins]"
    let got = (with-env {
        OCMTS_MATRIX_ROLE_IMAGE: "ghcr.io/example/matrix-receiver:latest"
        OCMTS_FLOW_ROLE_IMAGE: "ghcr.io/example/flow-receiver:latest"
        OCMTS_VERSION_ROLE_IMAGE: "ghcr.io/example/version-receiver:latest"
        OCMTS_PLATFORM_ROLE_IMAGE: "ghcr.io/example/platform-receiver:latest"
    } {
        (resolve-platform-image
            {
                receiver_override_env: "OCMTS_PLATFORM_ROLE_IMAGE"
                override_env: "OCMTS_PLATFORM_GENERIC_IMAGE"
                default: "ghcr.io/example/platform-default:latest"
            }
            {
                receiver_override_env: "OCMTS_VERSION_ROLE_IMAGE"
                override_env: "OCMTS_VERSION_GENERIC_IMAGE"
                default: "ghcr.io/example/version-default:latest"
                by_scenario: {
                    "share-with__nextcloud__ocmgo": {
                        receiver_override_env: "OCMTS_MATRIX_ROLE_IMAGE"
                        override_env: "OCMTS_MATRIX_GENERIC_IMAGE"
                        default: "ghcr.io/example/matrix-default:latest"
                    }
                }
                by_flow: {
                    "share-with": {
                        receiver_override_env: "OCMTS_FLOW_ROLE_IMAGE"
                        override_env: "OCMTS_FLOW_GENERIC_IMAGE"
                        default: "ghcr.io/example/flow-default:latest"
                    }
                }
            }
            "receiver"
            "share-with__nextcloud__ocmgo"
            "share-with"
        )
    })
    [
        (assert-eq $got "ghcr.io/example/matrix-receiver:latest"
            "matrix-key receiver_override_env beats by_flow, version, and platform defaults")
    ]
}

def main [] {
    test-log "=== images/precedence Tests ==="
    let results = (
        (test-resolve-platform-image-matrix-role-env-wins)
        | append (test-resolve-platform-image-matrix-default-wins-over-flow-default)
        | append (test-resolve-image-matrix-default-wins-over-flow-default)
        | append (test-resolve-platform-image-receiver-matrix-role-env-wins)
    ) | flatten
    run-suite "images/precedence" $SUITE_PATH $results
}
