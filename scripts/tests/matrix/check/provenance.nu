# Provenance block validation tests.
# Run: nu scripts/tests/matrix/check/provenance.nu
# Returns exit 0 on all pass, exit 1 with details on failure.

const SUITE_PATH = path self

use ../../../lib/matrix/check/provenance.nu [check-provenance-blocks]
use ../../../lib/tests/assert.nu *
use ../../../lib/tests/runner.nu [run-suite]
use ../../../lib/tests/fixtures.nu [with-tmp-dir]

# Write a single valid public JSON file to the given directory.
def write-valid-file [dir: string, name: string] {
    let content = {
        schema_version: 1,
        generated_at: "2026-05-11T19:00:00.000000000Z",
        generator: "scripts/lib/matrix/gen.nu#build-matrix",
        producer: {name: "ocmts", version: "0.1.0"},
        sources: [
            {
                path: "config/matrix/capabilities.v1.nuon",
                sha256: "a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2",
            }
        ],
    }
    ($content | to json) | save --force ($dir | path join $name)
}

# Writes all 4 required files with valid content.
def write-all-valid [public_dir: string] {
    mkdir $public_dir
    write-valid-file $public_dir "matrix-rules.v1.json"
    write-valid-file $public_dir "implemented-cells.v1.json"
    write-valid-file $public_dir "matrix-not-in-scope.v1.json"
    write-valid-file $public_dir "suite-manifest.v1.json"
}

# Set up tmp dirs: $tmp/ocmts/ as ocmts_root, $tmp/ocm-web-site/public/ as public dir.
def make-site-root [tmp: string]: nothing -> record {
    let ocmts_root = ($tmp | path join "ocmts")
    let public_dir = ($tmp | path join "ocm-web-site/public")
    mkdir $ocmts_root
    {ocmts_root: $ocmts_root, public_dir: $public_dir}
}

# Skipped when sibling public dir does not exist.
def test-skips-when-no-public-dir [] {
    test-log "\n[test-skips-when-no-public-dir]"
    with-tmp-dir {|tmp|
        let dirs = (make-site-root $tmp)
        # Do NOT create the public_dir.
        let result = (check-provenance-blocks $dirs.ocmts_root)
        [
            (assert-eq $result.skipped true
                "skipped=true when public dir is absent")
            (assert-eq $result.violations []
                "violations is empty when skipped")
        ]
    }
}

# All valid files -> no violations.
def test-all-valid-no-violations [] {
    test-log "\n[test-all-valid-no-violations]"
    with-tmp-dir {|tmp|
        let dirs = (make-site-root $tmp)
        write-all-valid $dirs.public_dir
        let result = (check-provenance-blocks $dirs.ocmts_root)
        [
            (assert-eq $result.skipped false
                "not skipped when public dir exists")
            (assert-eq $result.violations []
                "no violations when all files are valid")
        ]
    }
}

# A missing file yields a violation.
def test-missing-file-violation [] {
    test-log "\n[test-missing-file-violation]"
    with-tmp-dir {|tmp|
        let dirs = (make-site-root $tmp)
        write-all-valid $dirs.public_dir
        # Remove one file.
        rm ($dirs.public_dir | path join "suite-manifest.v1.json")
        let result = (check-provenance-blocks $dirs.ocmts_root)
        [
            (assert-truthy (($result.violations | any {|v| $v.file == "suite-manifest.v1.json"}))
                "violation for missing suite-manifest.v1.json")
        ]
    }
}

# A file with an invalid sha256 yields a violation naming that file.
def test-bad-sha256-violation [] {
    test-log "\n[test-bad-sha256-violation]"
    with-tmp-dir {|tmp|
        let dirs = (make-site-root $tmp)
        write-all-valid $dirs.public_dir
        # Overwrite one file with a tampered sha256.
        let bad = {
            schema_version: 1,
            generated_at: "2026-05-11T19:00:00.000000000Z",
            generator: "scripts/lib/matrix/gen.nu#build-matrix",
            producer: {name: "ocmts", version: "0.1.0"},
            sources: [{path: "config/matrix/capabilities.v1.nuon", sha256: "not-a-sha256"}],
        }
        ($bad | to json) | save --force ($dirs.public_dir | path join "matrix-rules.v1.json")
        let result = (check-provenance-blocks $dirs.ocmts_root)
        let violations = $result.violations
        [
            (assert-truthy (($violations | any {|v| $v.file == "matrix-rules.v1.json"}))
                "violation for matrix-rules.v1.json with bad sha256")
            (assert-truthy ($violations
                | where {|v| $v.file == "matrix-rules.v1.json"}
                | any {|v| $v.issue | str contains "sha256"})
                "violation issue mentions sha256")
        ]
    }
}

# A file with a wrong producer yields a violation.
def test-bad-producer-violation [] {
    test-log "\n[test-bad-producer-violation]"
    with-tmp-dir {|tmp|
        let dirs = (make-site-root $tmp)
        write-all-valid $dirs.public_dir
        let bad = {
            schema_version: 1,
            generated_at: "2026-05-11T19:00:00.000000000Z",
            generator: "scripts/lib/matrix/gen.nu#build-matrix",
            producer: {name: "wrong-tool", version: "9.9.9"},
            sources: [{path: "config/matrix/capabilities.v1.nuon", sha256: "a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2"}],
        }
        ($bad | to json) | save --force ($dirs.public_dir | path join "implemented-cells.v1.json")
        let result = (check-provenance-blocks $dirs.ocmts_root)
        [
            (assert-truthy (($result.violations | any {|v| $v.file == "implemented-cells.v1.json"}))
                "violation for implemented-cells.v1.json with wrong producer")
        ]
    }
}

# A file with an invalid generator format yields a violation.
def test-bad-generator-violation [] {
    test-log "\n[test-bad-generator-violation]"
    with-tmp-dir {|tmp|
        let dirs = (make-site-root $tmp)
        write-all-valid $dirs.public_dir
        let bad = {
            schema_version: 1,
            generated_at: "2026-05-11T19:00:00.000000000Z",
            generator: "not/a/valid/generator",
            producer: {name: "ocmts", version: "0.1.0"},
            sources: [{path: "config/matrix/capabilities.v1.nuon", sha256: "a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2"}],
        }
        ($bad | to json) | save --force ($dirs.public_dir | path join "matrix-not-in-scope.v1.json")
        let result = (check-provenance-blocks $dirs.ocmts_root)
        [
            (assert-truthy (($result.violations | any {|v| $v.file == "matrix-not-in-scope.v1.json"}))
                "violation for matrix-not-in-scope.v1.json with bad generator")
        ]
    }
}

def main [] {
    test-log "=== matrix/check/provenance Tests ==="
    let results = ([]
        | append (test-skips-when-no-public-dir)
        | append (test-all-valid-no-violations)
        | append (test-missing-file-violation)
        | append (test-bad-sha256-violation)
        | append (test-bad-producer-violation)
        | append (test-bad-generator-violation)
    )
    run-suite "matrix/check/provenance" $SUITE_PATH $results
}
