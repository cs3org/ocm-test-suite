# Schema validation helpers for intermediate artifact documents.

# Assert that a document has the expected schema_version.
# Errors fast with an actionable message naming the source path on mismatch
# or when the field is absent.
export def assert-schema-version [
    doc: record,      # the document record to validate
    expected: int,    # expected schema_version value
    source: string,   # source path for actionable error messages
] {
    let actual = ($doc.schema_version? | default null)
    if $actual == null {
        error make {msg: $"($source): missing schema_version field \(expected ($expected)\)"}
    } else if $actual != $expected {
        error make {msg: $"($source): schema_version mismatch: got ($actual), expected ($expected)"}
    }
}
