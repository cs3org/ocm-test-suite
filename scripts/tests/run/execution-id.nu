# execution-id and matrix_key validation tests.
# Run: nu scripts/tests/run/execution-id.nu

const SUITE_PATH = path self

use ../../lib/run/execution-id.nu [
    validate-matrix-key
    validate-path-segment
    validate-artifact-name
    validate-pair
    validate-execution-id
    execution-artifacts-path
    execution-temp-path
]
use ../../lib/tests/assert.nu *
use ../../lib/tests/runner.nu [run-suite]

def test-validate-matrix-key-allows-one-party-shape [] {
    test-log "\n[test-validate-matrix-key-allows-one-party-shape]"
    let result = (
        try { validate-matrix-key "login__nextcloud" }
        catch {|e| $"error: ($e.msg)"}
    )
    [
        (assert-eq $result "login__nextcloud"
            "validate-matrix-key accepts flow__sender shape")
    ]
}

def test-validate-matrix-key-allows-two-party-shape [] {
    test-log "\n[test-validate-matrix-key-allows-two-party-shape]"
    let result = (
        try { validate-matrix-key "share-with__nextcloud__ocmgo" }
        catch {|e| $"error: ($e.msg)"}
    )
    [
        (assert-eq $result "share-with__nextcloud__ocmgo"
            "validate-matrix-key accepts flow__sender__receiver shape")
    ]
}

def test-validate-matrix-key-rejects-empty [] {
    test-log "\n[test-validate-matrix-key-rejects-empty]"
    let result = (
        try { validate-matrix-key ""; "ok" }
        catch {|e| $"error: ($e.msg)"}
    )
    [
        (assert-truthy ($result | str starts-with "error:")
            "validate-matrix-key rejects empty key")
        (assert-string-contains $result "must not be empty"
            "empty key error states the requirement")
    ]
}

def test-validate-matrix-key-rejects-fewer-than-two-segments [] {
    test-log "\n[test-validate-matrix-key-rejects-fewer-than-two-segments]"
    let result = (
        try { validate-matrix-key "login"; "ok" }
        catch {|e| $"error: ($e.msg)"}
    )
    [
        (assert-truthy ($result | str starts-with "error:")
            "validate-matrix-key rejects a single segment")
        (assert-string-contains $result "flow__sender"
            "fewer than two segments error states the documented shape")
    ]
}

def test-validate-matrix-key-rejects-slash [] {
    test-log "\n[test-validate-matrix-key-rejects-slash]"
    let result = (
        try { validate-matrix-key "login/nextcloud"; "ok" }
        catch {|e| $"error: ($e.msg)"}
    )
    [
        (assert-truthy ($result | str starts-with "error:")
            "validate-matrix-key rejects slash in key")
        (assert-string-contains $result "slash"
            "slash error names the invalid character")
    ]
}

def test-validate-matrix-key-rejects-invalid-segment-slugs [] {
    test-log "\n[test-validate-matrix-key-rejects-invalid-segment-slugs]"
    let result = (
        try { validate-matrix-key "login__NextCloud"; "ok" }
        catch {|e| $"error: ($e.msg)"}
    )
    [
        (assert-truthy ($result | str starts-with "error:")
            "validate-matrix-key rejects non-slug segment")
        (assert-string-contains $result "shape invalid"
            "invalid segment error states slug contract")
    ]
}

def test-validate-matrix-key-rejects-extra-segments [] {
    test-log "\n[test-validate-matrix-key-rejects-extra-segments]"
    let result = (
        try { validate-matrix-key "share-with__nextcloud__ocmgo__extra"; "ok" }
        catch {|e| $"error: ($e.msg)"}
    )
    [
        (assert-truthy ($result | str starts-with "error:")
            "validate-matrix-key rejects extra segments")
        (assert-string-contains $result "<flow>__<sender>[__<receiver>]"
            "extra segment error states the documented matrix_key contract")
    ]
}

def test-validate-path-segment-accepts-slug [] {
    test-log "\n[test-validate-path-segment-accepts-slug]"
    let result = (
        try { validate-path-segment "nextcloud-v33" "sender_platform" }
        catch {|e| $"error: ($e.msg)"}
    )
    [
        (assert-eq $result "nextcloud-v33"
            "validate-path-segment accepts lowercase slug")
    ]
}

def test-validate-path-segment-rejects-empty [] {
    test-log "\n[test-validate-path-segment-rejects-empty]"
    let result = (
        try { validate-path-segment "" "sender_platform"; "ok" }
        catch {|e| $"error: ($e.msg)"}
    )
    [
        (assert-truthy ($result | str starts-with "error:")
            "validate-path-segment rejects empty segment")
        (assert-string-contains $result "sender_platform"
            "empty segment error names the label")
    ]
}

def test-validate-execution-id-accepts-shape [] {
    test-log "\n[test-validate-execution-id-accepts-shape]"
    let result = (
        try { validate-execution-id "20260701t120000-a1b2c3d4" }
        catch {|e| $"error: ($e.msg)"}
    )
    [
        (assert-eq $result "20260701t120000-a1b2c3d4"
            "validate-execution-id accepts documented shape")
    ]
}

def test-validate-execution-id-rejects-traversal [] {
    test-log "\n[test-validate-execution-id-rejects-traversal]"
    let result = (
        try { validate-execution-id "../20260701t120000-a1b2c3d4"; "ok" }
        catch {|e| $"error: ($e.msg)"}
    )
    [
        (assert-truthy ($result | str starts-with "error:")
            "validate-execution-id rejects traversal")
        (assert-string-contains $result "path traversal"
            "traversal error names the rejection reason")
    ]
}

def test-execution-artifacts-path-builds-contract [] {
    test-log "\n[test-execution-artifacts-path-builds-contract]"
    let result = (
        execution-artifacts-path "/tmp/ocmts-root" "login" "nextcloud-v32" "20260701t120000-a1b2c3d4"
    )
    [
        (assert-eq $result "/tmp/ocmts-root/artifacts/login/nextcloud-v32/20260701t120000-a1b2c3d4"
            "execution-artifacts-path joins validated locator fields")
    ]
}

def test-execution-temp-path-builds-contract [] {
    test-log "\n[test-execution-temp-path-builds-contract]"
    let result = (execution-temp-path "20260701t120000-a1b2c3d4")
    [
        (assert-eq $result "/tmp/ocmts/20260701t120000-a1b2c3d4"
            "execution-temp-path joins validated execution_id")
    ]
}

def test-validate-artifact-name-delegates-to-path-segment [] {
    test-log "\n[test-validate-artifact-name-delegates-to-path-segment]"
    let result = (
        try { validate-artifact-name "cell-login-nextcloud-v33" }
        catch {|e| $"error: ($e.msg)"}
    )
    [
        (assert-eq $result "cell-login-nextcloud-v33"
            "validate-artifact-name accepts artifact slug")
    ]
}

def test-validate-pair-delegates-to-path-segment [] {
    test-log "\n[test-validate-pair-delegates-to-path-segment]"
    let result = (
        try { validate-pair "nextcloud-v33-ocmgo-v1" }
        catch {|e| $"error: ($e.msg)"}
    )
    [
        (assert-eq $result "nextcloud-v33-ocmgo-v1"
            "validate-pair accepts pair slug")
    ]
}

def main [] {
    test-log "=== run/execution-id Tests ==="
    let results = (
        (test-validate-matrix-key-allows-one-party-shape)
        | append (test-validate-matrix-key-allows-two-party-shape)
        | append (test-validate-matrix-key-rejects-empty)
        | append (test-validate-matrix-key-rejects-fewer-than-two-segments)
        | append (test-validate-matrix-key-rejects-slash)
        | append (test-validate-matrix-key-rejects-invalid-segment-slugs)
        | append (test-validate-matrix-key-rejects-extra-segments)
        | append (test-validate-path-segment-accepts-slug)
        | append (test-validate-path-segment-rejects-empty)
        | append (test-validate-execution-id-accepts-shape)
        | append (test-validate-execution-id-rejects-traversal)
        | append (test-execution-artifacts-path-builds-contract)
        | append (test-execution-temp-path-builds-contract)
        | append (test-validate-artifact-name-delegates-to-path-segment)
        | append (test-validate-pair-delegates-to-path-segment)
    ) | flatten
    run-suite "run/execution-id" $SUITE_PATH $results
}
