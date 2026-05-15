# Registry cross-check tests.
# Run: nu scripts/tests/matrix/check/registry-cross.nu
# Returns exit 0 on all pass, exit 1 with details on failure.

const SUITE_PATH = path self

use ../../../lib/matrix/check/registry-cross.nu [
    REGISTRY_TABLE_CAPABILITY
    build-expected-supported
    check-registry-table-coverage
    diff-registry-vs-supported
    registry-bound-capabilities
]
use ../../../lib/tests/assert.nu *
use ../../../lib/tests/runner.nu [run-suite]

# registry-bound-capabilities returns sorted unique cap names from REGISTRY_TABLE_CAPABILITY.
def test-registry-bound-capabilities [] {
    test-log "\n[test-registry-bound-capabilities]"
    let bound = (registry-bound-capabilities)
    let expected_caps = ($REGISTRY_TABLE_CAPABILITY | get capability | uniq | sort)
    [
        (assert-eq $bound $expected_caps
            "registry-bound-capabilities matches REGISTRY_TABLE_CAPABILITY")
        (assert-truthy (($bound | length) > 0)
            "registry-bound-capabilities is non-empty")
        (assert-truthy (not ("flow.login" in $bound))
            "flow.login is not registry-bound")
    ]
}

# build-expected-supported maps table entries to capability lists.
def test-build-expected-basic [] {
    test-log "\n[test-build-expected-basic]"
    let tables = {
        loginAdapters: ["nextcloud/v32" "nextcloud/v33"],
        shareWithFlowSenderAdapters: ["nextcloud/v32"],
    }
    let expected = (build-expected-supported $tables)
    [
        (assert-list-contains (($expected | get "nextcloud/v32") | default []) "op.login"
            "nextcloud/v32 has op.login capability")
        (assert-list-contains (($expected | get "nextcloud/v32") | default []) "flow.share-with.sender"
            "nextcloud/v32 has flow.share-with.sender capability")
        (assert-list-contains (($expected | get "nextcloud/v33") | default []) "op.login"
            "nextcloud/v33 has op.login capability")
        (assert-truthy (not ("flow.share-with.sender" in (($expected | get "nextcloud/v33") | default [])))
            "nextcloud/v33 does not have flow.share-with.sender")
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
        (assert-list-contains $caps "op.login"
            "ocmgo/v1 has op.login")
        (assert-list-contains $caps "op.provider-identity"
            "ocmgo/v1 has op.provider-identity")
        (assert-eq ($caps | length) 2
            "ocmgo/v1 has exactly 2 capabilities")
    ]
}

# diff-registry-vs-supported: no drift when sets are equal.
def test-diff-no-drift [] {
    test-log "\n[test-diff-no-drift]"
    let expected = {"nextcloud/v32": ["op.login" "flow.share-with.sender"]}
    let actual = {"nextcloud/v32": ["op.login" "flow.share-with.sender"]}
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
    let expected = {"nextcloud/v32": ["op.login"] "ocmgo/v1": ["op.login"]}
    let actual = {"nextcloud/v32": ["op.login"]}
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
    let expected = {"nextcloud/v32": ["op.login"]}
    let actual = {"nextcloud/v32": ["op.login"] "ocmgo/v1": ["op.login"]}
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
    let expected = {"nextcloud/v32": ["op.login" "flow.share-with.sender"]}
    let actual = {"nextcloud/v32": ["op.login"]}
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

# check-registry-table-coverage: happy path - exact set matches mapping.
def test-coverage-happy-path [] {
    test-log "\n[test-coverage-happy-path]"
    let all_tables = ($REGISTRY_TABLE_CAPABILITY | get table_name)
    let result = (try { check-registry-table-coverage $all_tables; "ok" } catch {|e| $"error: ($e.msg)"})
    [
        (assert-eq $result "ok" "exact table set passes without error")
    ]
}

# check-registry-table-coverage: new table in registry.ts not in mapping.
def test-coverage-missing-in-mapping [] {
    test-log "\n[test-coverage-missing-in-mapping]"
    let all_tables = ($REGISTRY_TABLE_CAPABILITY | get table_name)
    let extended = ($all_tables | append "revokeShareSenderAdapters")
    let result = (try { check-registry-table-coverage $extended; "ok" } catch {|e| $e.msg})
    [
        (assert-truthy ($result | str contains "revokeShareSenderAdapters")
            "error mentions revokeShareSenderAdapters")
        (assert-truthy ($result | str contains "out of date")
            "error contains 'out of date'")
    ]
}

# check-registry-table-coverage: stale entry in mapping (table removed from registry.ts).
def test-coverage-stale-in-mapping [] {
    test-log "\n[test-coverage-stale-in-mapping]"
    let all_tables = ($REGISTRY_TABLE_CAPABILITY | get table_name)
    let reduced = ($all_tables | where {|t| $t != "loginAdapters"})
    let result = (try { check-registry-table-coverage $reduced; "ok" } catch {|e| $e.msg})
    [
        (assert-truthy ($result | str contains "loginAdapters")
            "error mentions loginAdapters")
        (assert-truthy ($result | str contains "stale entries")
            "error contains 'stale entries'")
    ]
}

# check-registry-table-coverage: empty input triggers stale-entries error for all 10 tables.
def test-coverage-empty-input [] {
    test-log "\n[test-coverage-empty-input]"
    let result = (try { check-registry-table-coverage []; "ok" } catch {|e| $e.msg})
    let all_tables = ($REGISTRY_TABLE_CAPABILITY | get table_name)
    [
        (assert-truthy ($result | str contains "stale entries")
            "error contains 'stale entries' for empty input")
        (assert-truthy ($all_tables | all {|t| $result | str contains $t})
            "error mentions all 10 mapped tables")
    ]
}

def main [] {
    test-log "=== matrix/check/registry-cross Tests ==="
    let results = ([]
        | append (test-registry-bound-capabilities)
        | append (test-build-expected-basic)
        | append (test-build-expected-multiple-tables)
        | append (test-diff-no-drift)
        | append (test-diff-missing-key)
        | append (test-diff-extra-key)
        | append (test-diff-capability-drift)
        | append (test-coverage-happy-path)
        | append (test-coverage-missing-in-mapping)
        | append (test-coverage-stale-in-mapping)
        | append (test-coverage-empty-input)
    )
    run-suite "matrix/check/registry-cross" $SUITE_PATH $results
}
