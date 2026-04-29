# Registry cross-check tests.
# Run: nu scripts/tests/matrix/check/registry-cross.nu
# Returns exit 0 on all pass, exit 1 with details on failure.

const SUITE_PATH = path self

use ../../../lib/matrix/check/registry-cross.nu [
    build-expected-supported
    diff-registry-vs-supported
]
use ../../../lib/tests/assert.nu *
use ../../../lib/tests/runner.nu [run-suite]

# build-expected-supported maps table entries to capability lists.
def test-build-expected-basic [] {
    test-log "\n[test-build-expected-basic]"
    let tables = {
        loginAdapters: ["nextcloud/v32" "nextcloud/v33"],
        shareWithSenderAdapters: ["nextcloud/v32"],
    }
    let expected = (build-expected-supported $tables)
    [
        (assert-list-contains (($expected | get "nextcloud/v32") | default []) "login"
            "nextcloud/v32 has login capability")
        (assert-list-contains (($expected | get "nextcloud/v32") | default []) "share-with.sender"
            "nextcloud/v32 has share-with.sender capability")
        (assert-list-contains (($expected | get "nextcloud/v33") | default []) "login"
            "nextcloud/v33 has login capability")
        (assert-truthy (not ("share-with.sender" in (($expected | get "nextcloud/v33") | default [])))
            "nextcloud/v33 does not have share-with.sender")
    ]
}

# An adapter key appearing in multiple tables accumulates capabilities.
def test-build-expected-multiple-tables [] {
    test-log "\n[test-build-expected-multiple-tables]"
    let tables = {
        loginAdapters: ["ocmgo/v1"],
        providerIdentityAdapters: ["ocmgo/v1"],
    }
    let expected = (build-expected-supported $tables)
    let caps = ($expected | get "ocmgo/v1" | default [] | sort)
    [
        (assert-list-contains $caps "login"
            "ocmgo/v1 has login")
        (assert-list-contains $caps "provider-identity"
            "ocmgo/v1 has provider-identity")
        (assert-eq ($caps | length) 2
            "ocmgo/v1 has exactly 2 capabilities")
    ]
}

# diff-registry-vs-supported: no drift when sets are equal.
def test-diff-no-drift [] {
    test-log "\n[test-diff-no-drift]"
    let expected = {"nextcloud/v32": ["login" "share-with.sender"]}
    let actual = {"nextcloud/v32": ["login" "share-with.sender"]}
    let result = (diff-registry-vs-supported $expected $actual)
    [
        (assert-eq $result.missing_keys []
            "no missing keys")
        (assert-eq $result.extra_keys []
            "no extra keys")
        (assert-eq $result.drift []
            "no drift")
    ]
}

# diff-registry-vs-supported: key in expected but not in actual.
def test-diff-missing-key [] {
    test-log "\n[test-diff-missing-key]"
    let expected = {"nextcloud/v32": ["login"] "ocmgo/v1": ["login"]}
    let actual = {"nextcloud/v32": ["login"]}
    let result = (diff-registry-vs-supported $expected $actual)
    [
        (assert-list-contains $result.missing_keys "ocmgo/v1"
            "ocmgo/v1 appears in missing_keys")
        (assert-eq $result.extra_keys []
            "no extra keys")
    ]
}

# diff-registry-vs-supported: key in actual but not in expected.
def test-diff-extra-key [] {
    test-log "\n[test-diff-extra-key]"
    let expected = {"nextcloud/v32": ["login"]}
    let actual = {"nextcloud/v32": ["login"] "ocmgo/v1": ["login"]}
    let result = (diff-registry-vs-supported $expected $actual)
    [
        (assert-eq $result.missing_keys []
            "no missing keys")
        (assert-list-contains $result.extra_keys "ocmgo/v1"
            "ocmgo/v1 appears in extra_keys")
    ]
}

# diff-registry-vs-supported: same keys, different capability sets.
def test-diff-capability-drift [] {
    test-log "\n[test-diff-capability-drift]"
    let expected = {"nextcloud/v32": ["login" "share-with.sender"]}
    let actual = {"nextcloud/v32": ["login"]}
    let result = (diff-registry-vs-supported $expected $actual)
    [
        (assert-eq $result.missing_keys []
            "no missing keys")
        (assert-eq $result.extra_keys []
            "no extra keys")
        (assert-truthy (($result.drift | length) == 1)
            "one drift entry")
        (assert-eq ($result.drift | first).key "nextcloud/v32"
            "drift key is nextcloud/v32")
    ]
}

def main [] {
    test-log "=== matrix/check/registry-cross Tests ==="
    let results = ([]
        | append (test-build-expected-basic)
        | append (test-build-expected-multiple-tables)
        | append (test-diff-no-drift)
        | append (test-diff-missing-key)
        | append (test-diff-extra-key)
        | append (test-diff-capability-drift)
    )
    run-suite "matrix/check/registry-cross" $SUITE_PATH $results
}
