# Provenance block helper tests.
# Run: nu scripts/tests/site/provenance.nu
# Returns exit 0 on all pass, exit 1 with details on failure.

const SUITE_PATH = path self

use ../../lib/site/provenance.nu [hash-source build-provenance-block]
use ../../lib/tests/assert.nu *
use ../../lib/tests/runner.nu [run-suite]

# Derive the OCMTS repo root from the script's own path.
def ocmts-root [] {
    $SUITE_PATH | path dirname | path dirname | path dirname | path dirname
}

def fixture-args [] {
    {
        generator: "scripts/lib/site/manifest.nu#build-aggregated-manifest",
        producer: {name: "ocmts", version: "0.1.0"},
        sources: ["config/matrix/capabilities.v1.nuon"],
        ocmts_root: (ocmts-root),
    }
}

# build-provenance-block returns a record with the expected shape and values.
def test-build-shape [] {
    test-log "\n[test-build-shape]"
    let block = (build-provenance-block (fixture-args))
    [
        (assert-eq $block.schema_version 1
            "schema_version is 1")
        (assert-eq $block.generator
            "scripts/lib/site/manifest.nu#build-aggregated-manifest"
            "generator matches input")
        (assert-eq $block.producer.name "ocmts"
            "producer.name is ocmts")
        (assert-eq $block.producer.version "0.1.0"
            "producer.version is 0.1.0")
        (assert-truthy (($block.sources | length) == 1)
            "sources list has one entry")
        (assert-eq ($block.sources | first).path
            "config/matrix/capabilities.v1.nuon"
            "sources[0].path matches input")
        (assert-truthy (not (($block.sources | first).sha256 | is-empty))
            "sources[0].sha256 is non-empty")
    ]
}

# generated_at is a valid RFC3339 nanosecond timestamp (UTC).
def test-rfc3339nano [] {
    test-log "\n[test-rfc3339nano]"
    let block = (build-provenance-block (fixture-args))
    let matches = ($block.generated_at | parse --regex
        '^(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{9}Z)$')
    [
        (assert-truthy (($matches | length) == 1)
            "generated_at matches RFC3339 nanosecond format")
    ]
}

# hash-source returns the same sha256 on two calls for the same file.
def test-hash-source-deterministic [] {
    test-log "\n[test-hash-source-deterministic]"
    let root = (ocmts-root)
    let first = (hash-source "config/matrix/capabilities.v1.nuon" $root)
    let second = (hash-source "config/matrix/capabilities.v1.nuon" $root)
    [
        (assert-eq $first.sha256 $second.sha256
            "hash-source returns the same sha256 on repeated calls")
    ]
}

# build-provenance-block rejects an absolute generator path.
def test-build-rejects-absolute-generator [] {
    test-log "\n[test-build-rejects-absolute-generator]"
    let args = ((fixture-args) | update generator "/abs/path#fn")
    let result = (
        try { build-provenance-block $args; "no-error" } catch {|e| $"error: ($e.msg)"}
    )
    [
        (assert-truthy ($result | str starts-with "error:")
            "absolute generator causes an error")
        (assert-string-contains $result "/abs/path#fn"
            "error message names the offending generator value")
    ]
}

# build-provenance-block rejects absolute paths in sources[].
def test-build-rejects-absolute-source [] {
    test-log "\n[test-build-rejects-absolute-source]"
    let args = ((fixture-args) | update sources ["/abs/source/path"])
    let result = (
        try { build-provenance-block $args; "no-error" } catch {|e| $"error: ($e.msg)"}
    )
    [
        (assert-truthy ($result | str starts-with "error:")
            "absolute source path causes an error")
        (assert-string-contains $result "/abs/source/path"
            "error message names the offending source value")
    ]
}

def main [] {
    test-log "=== site/provenance Tests ==="
    let results = (
        (test-build-shape)
        | append (test-rfc3339nano)
        | append (test-hash-source-deterministic)
        | append (test-build-rejects-absolute-generator)
        | append (test-build-rejects-absolute-source)
    ) | flatten
    run-suite "site/provenance" $SUITE_PATH $results
}
