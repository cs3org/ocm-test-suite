# Tests for cypress-suite domain: --optimize flag and guardrails.
# Run: nu scripts/tests/test/cypress-suite.nu
# Returns exit 0 on all pass, exit 1 with details on failure.

const SUITE_PATH = path self

use ../../lib/tests/assert.nu *
use ../../lib/tests/runner.nu [run-suite]

# --optimize is accepted by the CLI (flag does not cause a parse error).
# We probe this by running with --optimize --site-dir /nonexistent and
# expecting the error to be about the path, not about an unknown flag.
def test-optimize-flag-accepted [] {
    test-log "\n[test-optimize-flag-accepted]"
    let bad_path = "/tmp/ocmts-suite-publish-test-nonexistent-999"
    let result = (
        ^nu "scripts/domains/test/mod.nu" "cypress" "suite"
            "--publish-site"
            "--optimize"
            "--site-dir" $bad_path
        | complete
    )
    [
        (assert-eq $result.exit_code 1 "--optimize with nonexistent --site-dir exits 1")
        (assert-truthy ($result.stderr | str contains "does not exist")
            "error is about missing path, not unknown --optimize flag")
    ]
}

# --optimize is rejected when combined with missing --publish-site:
# --site-dir requires --publish-site should fire first.
def test-optimize-site-dir-requires-publish-site [] {
    test-log "\n[test-optimize-site-dir-requires-publish-site]"
    let result = (
        ^nu "scripts/domains/test/mod.nu" "cypress" "suite"
            "--optimize"
            "--site-dir" "/tmp/some-site"
        | complete
    )
    [
        (assert-eq $result.exit_code 1 "exit 1 when --site-dir without --publish-site")
        (assert-truthy ($result.stderr | str contains "--site-dir requires --publish-site")
            "guardrail message present even with --optimize")
    ]
}

# --help exits 0 and the help text mentions --optimize.
def test-optimize-help-mentions-flag [] {
    test-log "\n[test-optimize-help-mentions-flag]"
    let result = (
        ^nu "scripts/domains/test/mod.nu" "cypress" "suite" "--help"
        | complete
    )
    [
        (assert-truthy ($result.exit_code == 0)
            "--help exits 0")
        (assert-truthy ($result.stdout | str contains "--optimize")
            "--help output mentions --optimize flag")
    ]
}

# --help does not mention the removed --skip-optimize flag.
def test-help-does-not-mention-skip-optimize [] {
    test-log "\n[test-help-does-not-mention-skip-optimize]"
    let result = (
        ^nu "scripts/domains/test/mod.nu" "cypress" "suite" "--help"
        | complete
    )
    [
        (assert-truthy ($result.exit_code == 0)
            "--help exits 0")
        (assert-truthy (not ($result.stdout | str contains "skip-optimize"))
            "--help output does not mention removed --skip-optimize flag")
    ]
}

def main [] {
    test-log "=== test/cypress-suite tests ==="
    let results = (
        (test-optimize-flag-accepted)
        | append (test-optimize-site-dir-requires-publish-site)
        | append (test-optimize-help-mentions-flag)
        | append (test-help-does-not-mention-skip-optimize)
    ) | flatten
    run-suite "test/cypress-suite" $SUITE_PATH $results
}
