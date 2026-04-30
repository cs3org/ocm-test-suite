# Registry cross-check: maps registry table names to capabilities and
# compares the registry's adapter keys (from registry.ts via the TS
# helper) against the supported-by-key set from the adapter capabilities
# SSOT.

export const REGISTRY_TABLE_CAPABILITY = [
    {table_name: "loginAdapters",                    capability: "op.login"},
    {table_name: "shareWithFlowSenderAdapters",      capability: "flow.share-with.sender"},
    {table_name: "shareWithFlowReceiverAdapters",    capability: "flow.share-with.receiver"},
    {table_name: "shareFileSenderAdapters",          capability: "op.share-file.sender"},
    {table_name: "shareFileReceiverAdapters",        capability: "op.share-file.receiver"},
    {table_name: "contactTokenSenderAdapters",       capability: "op.contact-token.sender"},
    {table_name: "contactTokenReceiverAdapters",     capability: "op.contact-token.receiver"},
    {table_name: "contactWayfSenderAdapters",        capability: "op.contact-wayf.sender"},
    {table_name: "contactWayfReceiverAdapters",      capability: "op.contact-wayf.receiver"},
    {table_name: "providerIdentityAdapters",         capability: "op.provider-identity"},
]

# Returns the unique sorted set of capability names present in REGISTRY_TABLE_CAPABILITY.
export def registry-bound-capabilities [] {
    $REGISTRY_TABLE_CAPABILITY
        | get capability
        | uniq
        | sort
}

# Invokes scripts/typescript/extract-registry-keys.ts and returns the
# parsed record. The caller controls registry_path so tests can point
# at fixtures.
export def extract-registry-tables [
    ocmts_root: string,
    registry_path: string,
] {
    let helper = ($ocmts_root | path join "scripts/typescript/extract-registry-keys.ts")
    ^bun run $helper $registry_path | from json
}

# Builds expected {adapter_key -> [capability]} map from extracted tables
# using REGISTRY_TABLE_CAPABILITY.
export def build-expected-supported [tables: record] {
    mut expected = {}
    for $row in $REGISTRY_TABLE_CAPABILITY {
        let keys = ($tables | get --optional $row.table_name | default [])
        for $k in $keys {
            let prev = ($expected | get --optional $k | default [])
            $expected = ($expected | upsert $k ($prev | append $row.capability | uniq | sort))
        }
    }
    $expected
}

# Compares expected (from registry.ts) vs actual (from JSON's supported entries).
# Returns {missing_keys, extra_keys, drift}.
#   missing_keys: keys present in expected but absent in actual
#   extra_keys:   keys present in actual but absent in expected
#   drift:        keys present in both but with differing capability sets
export def diff-registry-vs-supported [
    expected: record,
    actual: record,
] {
    let expected_keys = ($expected | columns)
    let actual_keys = ($actual | columns)
    let missing_keys = ($expected_keys | where {|k| not ($k in $actual_keys)} | sort)
    let extra_keys = ($actual_keys | where {|k| not ($k in $expected_keys)} | sort)
    let common = ($expected_keys | where {|k| $k in $actual_keys})
    let drift = ($common | each {|k|
        let exp = (($expected | get $k) | uniq | sort)
        let act = (($actual | get $k) | uniq | sort)
        if ($exp | str join ",") != ($act | str join ",") {
            {key: $k, expected: $exp, actual: $act}
        }
    } | compact | sort-by key)
    {missing_keys: $missing_keys, extra_keys: $extra_keys, drift: $drift}
}
