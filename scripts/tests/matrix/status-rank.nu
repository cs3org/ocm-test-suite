# Unit tests for scripts/lib/matrix/status-rank.nu.
# Run: nu scripts/tests/matrix/status-rank.nu

const SUITE_PATH = path self

use ../../lib/matrix/status-rank.nu [STATUS_RANK worst-status pick-worst-blocker]
use ../../lib/tests/assert.nu *
use ../../lib/tests/runner.nu [run-suite]

def test-status-rank-ordering [] {
    test-log "\n[test-status-rank-ordering]"
    [
        (assert-truthy (($STATUS_RANK | get "supported") < ($STATUS_RANK | get "placeholder")) "supported < placeholder")
        (assert-truthy (($STATUS_RANK | get "placeholder") < ($STATUS_RANK | get "test-implementation-pending")) "placeholder < test-implementation-pending")
        (assert-truthy (($STATUS_RANK | get "test-implementation-pending") < ($STATUS_RANK | get "vendor-unsupported")) "test-implementation-pending < vendor-unsupported")
        (assert-truthy (($STATUS_RANK | get "vendor-unsupported") < ($STATUS_RANK | get "vendor-out-of-scope")) "vendor-unsupported < vendor-out-of-scope")
    ]
}

def test-worst-status-empty [] {
    test-log "\n[test-worst-status-empty]"
    [
        (assert-eq (worst-status []) "supported" "empty list returns supported")
    ]
}

def test-worst-status-single [] {
    test-log "\n[test-worst-status-single]"
    [
        (assert-eq (worst-status ["supported"]) "supported" "single supported")
        (assert-eq (worst-status ["vendor-unsupported"]) "vendor-unsupported" "single vendor-unsupported")
        (assert-eq (worst-status ["vendor-out-of-scope"]) "vendor-out-of-scope" "single vendor-out-of-scope")
    ]
}

def test-worst-status-multiple [] {
    test-log "\n[test-worst-status-multiple]"
    let r1 = (worst-status ["supported" "test-implementation-pending" "vendor-unsupported"])
    let r2 = (worst-status ["supported" "vendor-out-of-scope"])
    [
        (assert-eq $r1 "vendor-unsupported" "worst of mixed is vendor-unsupported")
        (assert-eq $r2 "vendor-out-of-scope" "worst of supported+oos is vendor-out-of-scope")
    ]
}

def test-worst-status-unknown-errors [] {
    test-log "\n[test-worst-status-unknown-errors]"
    let result = (try { worst-status ["unknown-status"]; "no-error" } catch {|e| "error"})
    [
        (assert-eq $result "error" "unknown status errors")
    ]
}

def test-pick-worst-blocker-empty [] {
    test-log "\n[test-pick-worst-blocker-empty]"
    [
        (assert-eq (pick-worst-blocker []) null "empty list returns null")
    ]
}

def test-pick-worst-blocker-single [] {
    test-log "\n[test-pick-worst-blocker-single]"
    let b = {status: "vendor-unsupported", capability: "op.login"}
    [
        (assert-eq (pick-worst-blocker [$b]) $b "single blocker returned")
    ]
}

def test-pick-worst-blocker-multiple [] {
    test-log "\n[test-pick-worst-blocker-multiple]"
    let b1 = {status: "supported", capability: "op.login"}
    let b2 = {status: "vendor-out-of-scope", capability: "op.share-file.sender"}
    let b3 = {status: "test-implementation-pending", capability: "op.contact-wayf.sender"}
    let result = (pick-worst-blocker [$b1 $b2 $b3])
    [
        (assert-eq ($result.status) "vendor-out-of-scope" "worst of multiple is vendor-out-of-scope")
    ]
}

def test-pick-worst-blocker-missing-status [] {
    test-log "\n[test-pick-worst-blocker-missing-status]"
    let b = {capability: "op.login"}
    let result = (pick-worst-blocker [$b])
    [
        (assert-eq ($result.capability) "op.login" "blocker without status returned by key")
    ]
}

def main [] {
    test-log "=== matrix/status-rank tests ==="
    let results = (
        (test-status-rank-ordering)
        | append (test-worst-status-empty)
        | append (test-worst-status-single)
        | append (test-worst-status-multiple)
        | append (test-worst-status-unknown-errors)
        | append (test-pick-worst-blocker-empty)
        | append (test-pick-worst-blocker-single)
        | append (test-pick-worst-blocker-multiple)
        | append (test-pick-worst-blocker-missing-status)
    ) | flatten
    run-suite "matrix/status-rank" $SUITE_PATH $results
}
