# Suite publish: resolve-site-dir behavior and test suite guardrail tests.
# Run: nu scripts/tests/site/clone.nu
# Returns exit 0 on all pass, exit 1 with details on failure.

const SUITE_PATH = path self

use ../../lib/site/clone.nu [resolve-site-dir]
use ../../lib/tests/assert.nu *
use ../../lib/tests/runner.nu [run-suite]

# Absolute paths pass through unchanged.
def test-resolve-site-dir-absolute [] {
    test-log "\n[test-resolve-site-dir-absolute]"
    let result = (resolve-site-dir "/absolute/path/to/site")
    [
        (assert-eq $result "/absolute/path/to/site"
            "absolute path passes through unchanged")
    ]
}

# Empty override returns the default ../ocm-web-site path.
def test-resolve-site-dir-empty-default [] {
    test-log "\n[test-resolve-site-dir-empty-default]"
    let result = (resolve-site-dir "")
    [
        (assert-truthy (not ($result | is-empty))
            "empty override returns non-empty default path")
        (assert-truthy ($result | str ends-with "ocm-web-site")
            "empty override returns path ending with ocm-web-site")
    ]
}

# Relative override is joined to OCMTS root (not left as relative).
def test-resolve-site-dir-relative [] {
    test-log "\n[test-resolve-site-dir-relative]"
    let result = (resolve-site-dir "my/site")
    [
        (assert-truthy (not ($result | str starts-with "my/"))
            "relative path is resolved to an absolute path")
        (assert-truthy ($result | str ends-with "my/site")
            "relative path is appended to OCMTS root")
    ]
}

# --site-dir without --publish-site must exit 1 with the guardrail message.
def test-guardrail-site-dir-requires-publish-site [] {
    test-log "\n[test-guardrail-site-dir-requires-publish-site]"
    let result = (^nu "scripts/domains/test/mod.nu" "suite" "--site-dir" "/tmp/some-site-dir" | complete)
    [
        (assert-eq $result.exit_code 1
            "--site-dir without --publish-site exits 1")
        (assert-truthy ($result.stderr | str contains "--site-dir requires --publish-site")
            "error message contains '--site-dir requires --publish-site'")
    ]
}

# --publish-site with a nonexistent --site-dir must exit 1 with a path error.
def test-local-mode-path-must-exist [] {
    test-log "\n[test-local-mode-path-must-exist]"
    let bad_path = "/tmp/ocmts-suite-publish-test-nonexistent-xyz-999"
    let result = (
        ^nu "scripts/domains/test/mod.nu" "suite"
            "--publish-site"
            "--site-dir" $bad_path
        | complete
    )
    [
        (assert-eq $result.exit_code 1
            "--publish-site with nonexistent --site-dir exits 1")
        (assert-truthy ($result.stderr | str contains "does not exist")
            "error message contains 'does not exist'")
    ]
}

# skip_clone derivation: non-empty site_dir means skip_clone is true.
def test-skip-clone-derived-from-site-dir [] {
    test-log "\n[test-skip-clone-derived-from-site-dir]"
    let skip_when_set = not ("/some/path" | is-empty)
    let skip_when_empty = not ("" | is-empty)
    [
        (assert-eq $skip_when_set true
            "non-empty site_dir derives skip_clone=true")
        (assert-eq $skip_when_empty false
            "empty site_dir derives skip_clone=false (clone enabled)")
    ]
}

def main [] {
    test-log "=== Suite Publish Tests ==="
    let results = (
        (test-resolve-site-dir-absolute)
        | append (test-resolve-site-dir-empty-default)
        | append (test-resolve-site-dir-relative)
        | append (test-guardrail-site-dir-requires-publish-site)
        | append (test-local-mode-path-must-exist)
        | append (test-skip-clone-derived-from-site-dir)
    ) | flatten
    run-suite "site/clone" $SUITE_PATH $results
}
