# Tests for cypress-suite domain: --skip-optimize flag and guardrails.
# Run: nu scripts/tests/test/cypress-suite.nu
# Returns exit 0 on all pass, exit 1 with details on failure.

const SUITE_PATH = path self

use ../../lib/tests/assert.nu *
use ../../lib/tests/runner.nu [run-suite]

# --skip-optimize is accepted by the CLI (flag does not cause a parse error).
# We probe this by running with --skip-optimize --site-dir /nonexistent and
# expecting the error to be about the path, not about an unknown flag.
def test-skip-optimize-flag-accepted [] {
    test-log "\n[test-skip-optimize-flag-accepted]"
    let bad_path = "/tmp/ocmts-suite-publish-test-nonexistent-skip-opt-999"
    let result = (
        ^nu "scripts/domains/test/mod.nu" "cypress" "suite"
            "--publish-site"
            "--skip-optimize"
            "--site-dir" $bad_path
        | complete
    )
    [
        (assert-eq $result.exit_code 1 "--skip-optimize with nonexistent --site-dir exits 1")
        (assert-truthy ($result.stderr | str contains "does not exist")
            "error is about missing path, not unknown --skip-optimize flag")
    ]
}

# --skip-optimize is rejected when combined with missing --publish-site:
# --site-dir requires --publish-site should fire first.
def test-skip-optimize-site-dir-requires-publish-site [] {
    test-log "\n[test-skip-optimize-site-dir-requires-publish-site]"
    let result = (
        ^nu "scripts/domains/test/mod.nu" "cypress" "suite"
            "--skip-optimize"
            "--site-dir" "/tmp/some-site"
        | complete
    )
    [
        (assert-eq $result.exit_code 1 "exit 1 when --site-dir without --publish-site")
        (assert-truthy ($result.stderr | str contains "--site-dir requires --publish-site")
            "guardrail message present even with --skip-optimize")
    ]
}

# --skip-optimize alone (no --publish-site) is a no-op flag: suite runs without
# the publish step. We verify the CLI accepts the flag without erroring on it.
def test-skip-optimize-alone-no-error [] {
    test-log "\n[test-skip-optimize-alone-no-error]"
    # Use --help which prints usage and exits 0; it exercises flag parsing without
    # starting any test infrastructure.
    let result = (
        ^nu "scripts/domains/test/mod.nu" "cypress" "suite" "--help"
        | complete
    )
    # --help should print usage and exit 0; the help text must mention --skip-optimize.
    let has_flag = ($result.stdout | str contains "skip-optimize")
    [
        (assert-truthy ($result.exit_code == 0)
            "--help exits 0")
        (assert-truthy $has_flag
            "--help output mentions --skip-optimize flag")
    ]
}

def main [] {
    test-log "=== test/cypress-suite tests ==="
    let results = (
        (test-skip-optimize-flag-accepted)
        | append (test-skip-optimize-site-dir-requires-publish-site)
        | append (test-skip-optimize-alone-no-error)
    ) | flatten
    run-suite "test/cypress-suite" $SUITE_PATH $results
}
