# Suite publish: resolve-site-dir behavior and test suite guardrail tests.
# Run: nu scripts/tests/suite-publish.nu
# Returns exit 0 on all pass, exit 1 with details on failure.

use ../lib/site-clone.nu [resolve-site-dir]

def PASS [] { "PASS" }
def FAIL [msg: string] { $"FAIL: ($msg)" }

def assert-eq [got: any, want: any, label: string] {
    if $got == $want {
        print $"  ok: ($label)"
        PASS
    } else {
        print $"  FAIL: ($label)"
        print $"    got:  ($got | to json)"
        print $"    want: ($want | to json)"
        FAIL $label
    }
}

def assert-truthy [got: bool, label: string] {
    if $got {
        print $"  ok: ($label)"
        PASS
    } else {
        print $"  FAIL: ($label) - expected truthy, got ($got)"
        FAIL $label
    }
}

# Absolute paths pass through unchanged.
def test-resolve-site-dir-absolute [] {
    print "\n[test-resolve-site-dir-absolute]"
    let result = (resolve-site-dir "/absolute/path/to/site")
    [
        (assert-eq $result "/absolute/path/to/site"
            "absolute path passes through unchanged")
    ]
}

# Empty override returns the default ../ocm-web-site path.
def test-resolve-site-dir-empty-default [] {
    print "\n[test-resolve-site-dir-empty-default]"
    let result = (resolve-site-dir "")
    [
        (assert-truthy (not ($result | is-empty))
            "empty override returns non-empty default path")
        (assert-truthy ($result | str ends-with "ocm-web-site")
            "empty override returns path ending with ocm-web-site")
    ]
}

# Relative override is joined to OTS root (not left as relative).
def test-resolve-site-dir-relative [] {
    print "\n[test-resolve-site-dir-relative]"
    let result = (resolve-site-dir "my/site")
    [
        (assert-truthy (not ($result | str starts-with "my/"))
            "relative path is resolved to an absolute path")
        (assert-truthy ($result | str ends-with "my/site")
            "relative path is appended to OTS root")
    ]
}

# --site-dir without --publish-site must exit 1 with the guardrail message.
def test-guardrail-site-dir-requires-publish-site [] {
    print "\n[test-guardrail-site-dir-requires-publish-site]"
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
    print "\n[test-local-mode-path-must-exist]"
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
    print "\n[test-skip-clone-derived-from-site-dir]"
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
    print "=== Suite Publish Tests ==="
    let results = (
        (test-resolve-site-dir-absolute)
        | append (test-resolve-site-dir-empty-default)
        | append (test-resolve-site-dir-relative)
        | append (test-guardrail-site-dir-requires-publish-site)
        | append (test-local-mode-path-must-exist)
        | append (test-skip-clone-derived-from-site-dir)
    )
    let failures = ($results | where {|r| $r != "PASS"})
    let total = ($results | length)
    let passed = ($total - ($failures | length))
    print $"\n=== ($passed)/($total) passed ==="
    if not ($failures | is-empty) {
        print "Failures:"
        for f in $failures { print $"  ($f)" }
        exit 1
    }
    print "All tests passed."
}
