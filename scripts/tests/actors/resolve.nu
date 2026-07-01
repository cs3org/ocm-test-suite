# Actor platform/account resolver unit tests.
# Run: nu scripts/tests/actors/resolve.nu

const SUITE_PATH = path self

use ../../lib/actors/resolve.nu [resolve-platform resolve-account]
use ../../lib/tests/assert.nu *
use ../../lib/tests/runner.nu [run-suite]

def test-resolve-platform-override-mismatch-errors [] {
    test-log "\n[test-resolve-platform-override-mismatch-errors]"
    let result = (
        try { resolve-platform "ocmgo" "nextcloud" "nextcloud" "sender" }
        catch {|e| $e.msg}
    )
    [
        (assert-string-contains $result "mismatches expected"
            "override platform mismatch names mismatches expected")
        (assert-string-contains $result "ocmgo"
            "override platform mismatch names cfg platform")
        (assert-string-contains $result "nextcloud"
            "override platform mismatch names expected platform")
        (assert-string-contains $result "sender"
            "override platform mismatch names role label")
    ]
}

def test-resolve-platform-override-wins-when-consistent [] {
    test-log "\n[test-resolve-platform-override-wins-when-consistent]"
    let platform = (resolve-platform "nextcloud" "nextcloud" "ocmgo" "sender")
    [
        (assert-eq $platform "nextcloud"
            "consistent override platform wins over matrix fallback")
    ]
}

def test-resolve-platform-falls-back-to-matrix [] {
    test-log "\n[test-resolve-platform-falls-back-to-matrix]"
    let platform = (resolve-platform "" "" "nextcloud" "receiver")
    [
        (assert-eq $platform "nextcloud"
            "empty override and expected fall back to matrix platform")
    ]
}

def test-resolve-account-from-defaults [] {
    test-log "\n[test-resolve-account-from-defaults]"
    let defaults = {
        flows: {
            login: {actor: {by_platform: {nextcloud: "michiel"}}}
        }
    }
    let account = (resolve-account $defaults "login" "actor" "nextcloud" "" "actor")
    [
        (assert-eq $account "michiel"
            "resolve-account reads defaults by flow, role, and platform")
    ]
}

def test-resolve-account-two-party-from-defaults [] {
    test-log "\n[test-resolve-account-two-party-from-defaults]"
    let defaults = {
        flows: {
            "share-with": {
                sender: {by_platform: {nextcloud: "michiel"}},
                receiver: {by_platform: {ocmgo: "marie"}},
            }
        }
    }
    let sender_account = (
        resolve-account $defaults "share-with" "sender" "nextcloud" "" "sender"
    )
    let receiver_account = (
        resolve-account $defaults "share-with" "receiver" "ocmgo" "" "receiver"
    )
    [
        (assert-eq $sender_account "michiel"
            "resolve-account reads two-party sender defaults")
        (assert-eq $receiver_account "marie"
            "resolve-account reads two-party receiver defaults")
    ]
}

def main [] {
    test-log "=== actors/resolve Tests ==="
    let results = (
        (test-resolve-platform-override-mismatch-errors)
        | append (test-resolve-platform-override-wins-when-consistent)
        | append (test-resolve-platform-falls-back-to-matrix)
        | append (test-resolve-account-from-defaults)
        | append (test-resolve-account-two-party-from-defaults)
    ) | flatten
    run-suite "actors/resolve" $SUITE_PATH $results
}
