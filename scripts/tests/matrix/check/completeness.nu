# Capability completeness check tests.
# Run: nu scripts/tests/matrix/check/completeness.nu
# Returns exit 0 on all pass, exit 1 with details on failure.

const SUITE_PATH = path self

use ../../../lib/matrix/check/completeness.nu [check-capability-completeness]
use ../../../lib/tests/assert.nu *
use ../../../lib/tests/runner.nu [run-suite]
use ../../../lib/tests/fixtures.nu [with-tmp-dir]

# Write a capabilities.v1.nuon with the given list to tmp_root.
def write-caps-config [tmp_root: string, caps: list<string>] {
    mkdir ($tmp_root | path join "config/matrix")
    let cfg = {schema_version: 1, capabilities: $caps}
    ($cfg | to json) | save --force ($tmp_root | path join "config/matrix/capabilities.v1.nuon")
}

# All adapters have all canonical capabilities -> no missing entries.
def test-no-missing [] {
    test-log "\n[test-no-missing]"
    with-tmp-dir {|tmp|
        write-caps-config $tmp ["login" "share-with.sender"]
        let adapters = {
            "nextcloud/v32": {capabilities: {login: {status: "supported"}, "share-with.sender": {status: "supported"}}},
            "ocmgo/v1":      {capabilities: {login: {status: "supported"}, "share-with.sender": {status: "vendor-unsupported", tracking_note: "n/a"}}},
        }
        let result = (check-capability-completeness $tmp $adapters)
        [
            (assert-eq $result.missing []
                "missing is empty when all adapters have all canonical caps")
            (assert-eq $result.canonical ["login" "share-with.sender"]
                "canonical matches config")
        ]
    }
}

# One adapter is missing a canonical capability.
def test-missing-one-cap [] {
    test-log "\n[test-missing-one-cap]"
    with-tmp-dir {|tmp|
        write-caps-config $tmp ["login" "share-with.sender"]
        let adapters = {
            "nextcloud/v32": {capabilities: {login: {status: "supported"}}},
        }
        let result = (check-capability-completeness $tmp $adapters)
        [
            (assert-truthy (($result.missing | length) == 1)
                "exactly one missing entry")
            (assert-eq ($result.missing | first).adapter_key "nextcloud/v32"
                "missing adapter_key is nextcloud/v32")
            (assert-eq ($result.missing | first).capability_key "share-with.sender"
                "missing capability_key is share-with.sender")
        ]
    }
}

# Two adapters, each missing a different capability.
def test-missing-across-adapters [] {
    test-log "\n[test-missing-across-adapters]"
    with-tmp-dir {|tmp|
        write-caps-config $tmp ["login" "share-with.sender" "provider-identity"]
        let adapters = {
            "nextcloud/v32": {capabilities: {login: {status: "supported"}, "share-with.sender": {status: "supported"}}},
            "ocmgo/v1":      {capabilities: {login: {status: "supported"}, "provider-identity": {status: "supported"}}},
        }
        let result = (check-capability-completeness $tmp $adapters)
        let missing_keys = ($result.missing | each {|m| $"($m.adapter_key)/($m.capability_key)"})
        [
            (assert-truthy (($result.missing | length) == 2)
                "two missing entries total")
            (assert-list-contains $missing_keys "nextcloud/v32/provider-identity"
                "nextcloud/v32 is missing provider-identity")
            (assert-list-contains $missing_keys "ocmgo/v1/share-with.sender"
                "ocmgo/v1 is missing share-with.sender")
        ]
    }
}

def main [] {
    test-log "=== matrix/check/completeness Tests ==="
    let results = ([]
        | append (test-no-missing)
        | append (test-missing-one-cap)
        | append (test-missing-across-adapters)
    )
    run-suite "matrix/check/completeness" $SUITE_PATH $results
}
