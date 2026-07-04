# Image precedence unit tests (pure functions, synthetic fixtures).
# Proves the scope-first contract: narrower scope wins entirely before a
# broader scope is considered, and within a scope role env beats generic
# env beats default.
# Run: nu scripts/tests/images/precedence.nu

const SUITE_PATH = path self

use ../../lib/images/precedence.nu [resolve-image resolve-platform-image]
use ../../lib/tests/assert.nu *
use ../../lib/tests/runner.nu [run-suite]

const MATRIX_KEY = "share-with__nextcloud__ocmgo"
const FLOW_ID = "share-with"

# ---- resolve-image: generic 6-level scope-first leaf precedence ----

def generic-leaf-spec [] {
    {
        override_env: "OCMTS_LEAF_GENERIC_IMAGE"
        default: "ghcr.io/example/leaf-default:latest"
        by_flow: {
            ($FLOW_ID): {
                override_env: "OCMTS_FLOW_GENERIC_IMAGE"
                default: "ghcr.io/example/flow-default:latest"
            }
        }
        by_matrix_key: {
            ($MATRIX_KEY): {
                override_env: "OCMTS_MATRIX_GENERIC_IMAGE"
                default: "ghcr.io/example/matrix-default:latest"
            }
        }
    }
}

def test-resolve-image-matrix-env-wins-over-everything [] {
    test-log "\n[test-resolve-image-matrix-env-wins-over-everything]"
    let got = (with-env {
        OCMTS_MATRIX_GENERIC_IMAGE: "ghcr.io/example/matrix-env:latest"
        OCMTS_FLOW_GENERIC_IMAGE: "ghcr.io/example/flow-env:latest"
        OCMTS_LEAF_GENERIC_IMAGE: "ghcr.io/example/leaf-env:latest"
    } {
        resolve-image (generic-leaf-spec) $MATRIX_KEY $FLOW_ID
    })
    [
        (assert-eq $got "ghcr.io/example/matrix-env:latest"
            "matrix override_env beats flow and leaf env and defaults")
    ]
}

def test-resolve-image-matrix-default-wins-over-flow-env [] {
    test-log "\n[test-resolve-image-matrix-default-wins-over-flow-env]"
    let got = (with-env {
        OCMTS_FLOW_GENERIC_IMAGE: "ghcr.io/example/flow-env:latest"
        OCMTS_LEAF_GENERIC_IMAGE: "ghcr.io/example/leaf-env:latest"
    } {
        resolve-image (generic-leaf-spec) $MATRIX_KEY $FLOW_ID
    })
    [
        (assert-eq $got "ghcr.io/example/matrix-default:latest"
            "matrix scope's own default beats flow override_env: scope wins before kind")
    ]
}

def test-resolve-image-flow-env-wins-over-leaf-env [] {
    test-log "\n[test-resolve-image-flow-env-wins-over-leaf-env]"
    let got = (with-env {
        OCMTS_FLOW_GENERIC_IMAGE: "ghcr.io/example/flow-env:latest"
        OCMTS_LEAF_GENERIC_IMAGE: "ghcr.io/example/leaf-env:latest"
    } {
        resolve-image (generic-leaf-spec) "" $FLOW_ID
    })
    [
        (assert-eq $got "ghcr.io/example/flow-env:latest"
            "flow override_env beats leaf env and default when no matrix key matches")
    ]
}

def test-resolve-image-flow-default-wins-over-leaf-env [] {
    test-log "\n[test-resolve-image-flow-default-wins-over-leaf-env]"
    let got = (with-env {
        OCMTS_LEAF_GENERIC_IMAGE: "ghcr.io/example/leaf-env:latest"
    } {
        resolve-image (generic-leaf-spec) "" $FLOW_ID
    })
    [
        (assert-eq $got "ghcr.io/example/flow-default:latest"
            "flow scope's own default beats leaf override_env: scope wins before kind")
    ]
}

def test-resolve-image-leaf-env-wins-over-leaf-default [] {
    test-log "\n[test-resolve-image-leaf-env-wins-over-leaf-default]"
    let got = (with-env {
        OCMTS_LEAF_GENERIC_IMAGE: "ghcr.io/example/leaf-env:latest"
    } {
        resolve-image (generic-leaf-spec) "" ""
    })
    [
        (assert-eq $got "ghcr.io/example/leaf-env:latest"
            "leaf override_env beats leaf default when no matrix or flow scope applies")
    ]
}

def test-resolve-image-leaf-default-is-final-fallback [] {
    test-log "\n[test-resolve-image-leaf-default-is-final-fallback]"
    let got = (resolve-image {default: "ghcr.io/example/leaf-default-only:latest"} "" "")
    [
        (assert-eq $got "ghcr.io/example/leaf-default-only:latest"
            "leaf default applies when no scope and no env override exist")
    ]
}

# ---- resolve-platform-image: 9-level scope-first role-aware precedence ----

def platform-version-spec [] {
    {
        sender_override_env: "OCMTS_VERSION_ROLE_IMAGE"
        override_env: "OCMTS_VERSION_GENERIC_IMAGE"
        default: "ghcr.io/example/version-default:latest"
        by_flow: {
            ($FLOW_ID): {
                sender_override_env: "OCMTS_FLOW_ROLE_IMAGE"
                override_env: "OCMTS_FLOW_GENERIC_IMAGE"
                default: "ghcr.io/example/flow-default:latest"
            }
        }
        by_matrix_key: {
            ($MATRIX_KEY): {
                sender_override_env: "OCMTS_MATRIX_ROLE_IMAGE"
                override_env: "OCMTS_MATRIX_GENERIC_IMAGE"
                default: "ghcr.io/example/matrix-default:latest"
            }
        }
    }
}

def test-resolve-platform-image-matrix-role-env-wins-over-everything [] {
    test-log "\n[test-resolve-platform-image-matrix-role-env-wins-over-everything]"
    let got = (with-env {
        OCMTS_MATRIX_ROLE_IMAGE: "ghcr.io/example/matrix-role:latest"
        OCMTS_MATRIX_GENERIC_IMAGE: "ghcr.io/example/matrix-generic:latest"
        OCMTS_FLOW_ROLE_IMAGE: "ghcr.io/example/flow-role:latest"
        OCMTS_VERSION_ROLE_IMAGE: "ghcr.io/example/version-role:latest"
    } {
        resolve-platform-image (platform-version-spec) "sender" $MATRIX_KEY $FLOW_ID
    })
    [
        (assert-eq $got "ghcr.io/example/matrix-role:latest"
            "matrix-key sender_override_env beats matrix generic env, flow, and version")
    ]
}

def test-resolve-platform-image-matrix-generic-env-wins-over-flow-role-env [] {
    test-log "\n[test-resolve-platform-image-matrix-generic-env-wins-over-flow-role-env]"
    let got = (with-env {
        OCMTS_MATRIX_GENERIC_IMAGE: "ghcr.io/example/matrix-generic:latest"
        OCMTS_FLOW_ROLE_IMAGE: "ghcr.io/example/flow-role:latest"
        OCMTS_VERSION_ROLE_IMAGE: "ghcr.io/example/version-role:latest"
    } {
        resolve-platform-image (platform-version-spec) "sender" $MATRIX_KEY $FLOW_ID
    })
    [
        (assert-eq $got "ghcr.io/example/matrix-generic:latest"
            "matrix generic override_env beats flow role_override_env: scope wins before kind")
    ]
}

def test-resolve-platform-image-matrix-default-wins-over-flow-role-env [] {
    test-log "\n[test-resolve-platform-image-matrix-default-wins-over-flow-role-env]"
    let got = (with-env {
        OCMTS_FLOW_ROLE_IMAGE: "ghcr.io/example/flow-role:latest"
        OCMTS_VERSION_ROLE_IMAGE: "ghcr.io/example/version-role:latest"
    } {
        resolve-platform-image (platform-version-spec) "sender" $MATRIX_KEY $FLOW_ID
    })
    [
        (assert-eq $got "ghcr.io/example/matrix-default:latest"
            "matrix-key scope's own default beats flow role env and version role env")
    ]
}

def test-resolve-platform-image-flow-role-env-wins-when-no-matrix-key [] {
    test-log "\n[test-resolve-platform-image-flow-role-env-wins-when-no-matrix-key]"
    let got = (with-env {
        OCMTS_FLOW_ROLE_IMAGE: "ghcr.io/example/flow-role:latest"
        OCMTS_FLOW_GENERIC_IMAGE: "ghcr.io/example/flow-generic:latest"
        OCMTS_VERSION_ROLE_IMAGE: "ghcr.io/example/version-role:latest"
    } {
        resolve-platform-image (platform-version-spec) "sender" "" $FLOW_ID
    })
    [
        (assert-eq $got "ghcr.io/example/flow-role:latest"
            "flow sender_override_env beats flow generic env and version when no matrix key matches")
    ]
}

def test-resolve-platform-image-flow-generic-env-wins-over-version-role-env [] {
    test-log "\n[test-resolve-platform-image-flow-generic-env-wins-over-version-role-env]"
    let got = (with-env {
        OCMTS_FLOW_GENERIC_IMAGE: "ghcr.io/example/flow-generic:latest"
        OCMTS_VERSION_ROLE_IMAGE: "ghcr.io/example/version-role:latest"
    } {
        resolve-platform-image (platform-version-spec) "sender" "" $FLOW_ID
    })
    [
        (assert-eq $got "ghcr.io/example/flow-generic:latest"
            "flow generic override_env beats version role_override_env: scope wins before kind")
    ]
}

def test-resolve-platform-image-flow-default-wins-over-version-role-env [] {
    test-log "\n[test-resolve-platform-image-flow-default-wins-over-version-role-env]"
    let got = (with-env {
        OCMTS_VERSION_ROLE_IMAGE: "ghcr.io/example/version-role:latest"
    } {
        resolve-platform-image (platform-version-spec) "sender" "" $FLOW_ID
    })
    [
        (assert-eq $got "ghcr.io/example/flow-default:latest"
            "flow scope's own default beats version role env: scope wins before kind")
    ]
}

def test-resolve-platform-image-version-role-env-wins-over-generic [] {
    test-log "\n[test-resolve-platform-image-version-role-env-wins-over-generic]"
    let got = (with-env {
        OCMTS_VERSION_ROLE_IMAGE: "ghcr.io/example/version-role:latest"
        OCMTS_VERSION_GENERIC_IMAGE: "ghcr.io/example/version-generic:latest"
    } {
        resolve-platform-image (platform-version-spec) "sender" "" ""
    })
    [
        (assert-eq $got "ghcr.io/example/version-role:latest"
            "version sender_override_env beats version generic override_env")
    ]
}

def test-resolve-platform-image-version-generic-env-wins-over-default [] {
    test-log "\n[test-resolve-platform-image-version-generic-env-wins-over-default]"
    let got = (with-env {
        OCMTS_VERSION_GENERIC_IMAGE: "ghcr.io/example/version-generic:latest"
    } {
        resolve-platform-image (platform-version-spec) "sender" "" ""
    })
    [
        (assert-eq $got "ghcr.io/example/version-generic:latest"
            "version generic override_env beats version default")
    ]
}

def test-resolve-platform-image-version-default-is-final-fallback [] {
    test-log "\n[test-resolve-platform-image-version-default-is-final-fallback]"
    let got = (resolve-platform-image {default: "ghcr.io/example/version-default-only:latest"} "sender" "" "")
    [
        (assert-eq $got "ghcr.io/example/version-default-only:latest"
            "version default applies when no scope and no env override exist")
    ]
}

def test-resolve-platform-image-receiver-role-isolated-from-sender [] {
    test-log "\n[test-resolve-platform-image-receiver-role-isolated-from-sender]"
    let spec = {
        sender_override_env: "OCMTS_SENDER_ONLY_IMAGE"
        receiver_override_env: "OCMTS_RECEIVER_ONLY_IMAGE"
        default: "ghcr.io/example/version-default:latest"
    }
    let got = (with-env {
        OCMTS_SENDER_ONLY_IMAGE: "ghcr.io/example/sender-leak:latest"
        OCMTS_RECEIVER_ONLY_IMAGE: "ghcr.io/example/receiver-role:latest"
    } {
        resolve-platform-image $spec "receiver" "" ""
    })
    [
        (assert-eq $got "ghcr.io/example/receiver-role:latest"
            "receiver resolution uses receiver_override_env and ignores sender_override_env")
    ]
}

def main [] {
    test-log "=== images/precedence Tests ==="
    let results = (
        (test-resolve-image-matrix-env-wins-over-everything)
        | append (test-resolve-image-matrix-default-wins-over-flow-env)
        | append (test-resolve-image-flow-env-wins-over-leaf-env)
        | append (test-resolve-image-flow-default-wins-over-leaf-env)
        | append (test-resolve-image-leaf-env-wins-over-leaf-default)
        | append (test-resolve-image-leaf-default-is-final-fallback)
        | append (test-resolve-platform-image-matrix-role-env-wins-over-everything)
        | append (test-resolve-platform-image-matrix-generic-env-wins-over-flow-role-env)
        | append (test-resolve-platform-image-matrix-default-wins-over-flow-role-env)
        | append (test-resolve-platform-image-flow-role-env-wins-when-no-matrix-key)
        | append (test-resolve-platform-image-flow-generic-env-wins-over-version-role-env)
        | append (test-resolve-platform-image-flow-default-wins-over-version-role-env)
        | append (test-resolve-platform-image-version-role-env-wins-over-generic)
        | append (test-resolve-platform-image-version-generic-env-wins-over-default)
        | append (test-resolve-platform-image-version-default-is-final-fallback)
        | append (test-resolve-platform-image-receiver-role-isolated-from-sender)
    ) | flatten
    run-suite "images/precedence" $SUITE_PATH $results
}
