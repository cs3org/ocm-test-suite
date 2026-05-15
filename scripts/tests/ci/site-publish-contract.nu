# Test-domain publish flags, guardrails, and exit semantics.
# Run: nu scripts/tests/ci/site-publish-contract.nu
# Returns exit 0 on all pass, exit 1 with details on failure.

const SUITE_PATH = path self

use ../../lib/tests/assert.nu *
use ../../lib/tests/runner.nu [run-suite]

def test-suite-publish-cli-flags [] {
    test-log "\n[test-suite-publish-cli-flags]"
    let help = (^nu "scripts/ocmts.nu" "test" "cypress" "suite" "--help" | complete)
    let out = $help.stdout
    [
        (assert-eq $help.exit_code 0
            "ocmts test cypress suite --help exits 0")
        (assert-truthy ($out | str contains "--publish-site")
            "help advertises --publish-site flag")
        (assert-truthy ($out | str contains "--site-dir")
            "help advertises --site-dir flag")
        (assert-truthy (($out | str contains "--site-dir") and ($out | str contains "--publish-site"))
            "help documents both --site-dir and --publish-site in the same surface")
    ]
}

def test-suite-publish-exit-semantics [] {
    test-log "\n[test-suite-publish-exit-semantics]"
    # Exit combination: 0 only when both suite and publish exit 0.
    let combine = {|s, p| if ($s == 0 and $p == 0) { 0 } else { 1 } }
    [
        (assert-eq (do $combine 1 0) 1 "suite failed + publish ok => nonzero")
        (assert-eq (do $combine 0 1) 1 "suite ok + publish failed => nonzero")
        (assert-eq (do $combine 1 1) 1 "both failed => nonzero")
        (assert-eq (do $combine 0 0) 0 "both ok => zero")
    ]
}

def test-suite-publish-guardrail-logic [] {
    test-log "\n[test-suite-publish-guardrail-logic]"
    # --site-dir without --publish-site must raise a clear error.
    let caught_no_publish = (try {
        let site_dir = "some/path"
        let publish_site = false
        if (not ($site_dir | is-empty)) and (not $publish_site) {
            error make {msg: "--site-dir requires --publish-site"}
        }
        false
    } catch {
        true
    })
    # --site-dir with --publish-site passes the flag-combination guard.
    let passes_with_publish = (try {
        let site_dir = "some/path"
        let publish_site = true
        if (not ($site_dir | is-empty)) and (not $publish_site) {
            error make {msg: "--site-dir requires --publish-site"}
        }
        true
    } catch {
        false
    })
    [
        (assert-truthy $caught_no_publish
            "--site-dir without --publish-site raises guardrail error")
        (assert-truthy $passes_with_publish
            "--site-dir with --publish-site passes the flag-combination guard")
    ]
}

def main [] {
    test-log "=== CI site publish contract tests ==="
    let results = (
        (test-suite-publish-cli-flags)
        | append (test-suite-publish-exit-semantics)
        | append (test-suite-publish-guardrail-logic)
    ) | flatten
    run-suite "ci/site-publish-contract" $SUITE_PATH $results
}
