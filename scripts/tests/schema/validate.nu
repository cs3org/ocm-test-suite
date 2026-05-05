# assert-schema-version unit tests.
# Run: nu scripts/tests/schema/validate.nu
# Returns exit 0 on all pass, exit 1 with details on failure.

const SUITE_PATH = path self

use ../../lib/schema/validate.nu [assert-schema-version]
use ../../lib/tests/assert.nu *
use ../../lib/tests/runner.nu [run-suite]

# Matching schema_version: no error.
def test-match [] {
    test-log "\n[test-match]"
    let ok = (try {
        assert-schema-version {schema_version: 1} 1 "test/match"
        true
    } catch {
        false
    })
    [(assert-truthy $ok "matching schema_version does not throw")]
}

# Mismatched schema_version: errors with actionable message.
def test-mismatch [] {
    test-log "\n[test-mismatch]"
    let threw = (try {
        assert-schema-version {schema_version: 2} 1 "test/source.json"
        false
    } catch {|e|
        ($e.msg | str contains "test/source.json")
    })
    [(assert-truthy $threw "mismatch throws an error naming the source path")]
}

# Missing schema_version field: errors with actionable message.
def test-missing-field [] {
    test-log "\n[test-missing-field]"
    let threw = (try {
        assert-schema-version {other_field: "x"} 1 "test/missing.json"
        false
    } catch {|e|
        ($e.msg | str contains "test/missing.json")
    })
    [(assert-truthy $threw "missing field throws an error naming the source path")]
}

def main [] {
    test-log "=== schema/validate Tests ==="
    let results = ([]
        | append (test-match)
        | append (test-mismatch)
        | append (test-missing-field)
    )
    run-suite "schema/validate" $SUITE_PATH $results
}
