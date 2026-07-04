# Test suite runner. Collects per-test results, prints a pass/fail
# summary, and exits non-zero on any failure. Honors OCMTS_TEST_JSON=1
# for machine-readable output (single JSON object on stdout, no human prose).

export def run-suite [suite_name: string, suite_path: string, results: list<string>]: nothing -> nothing {
    let total = ($results | length)
    let skipped_entries = ($results | where {|r| ($r | str starts-with "SKIP")})
    let failure_entries = ($results | where {|r| $r != "PASS" and not ($r | str starts-with "SKIP")})
    let skipped = ($skipped_entries | length)
    let failed = ($failure_entries | length)
    let passed = ($total - $failed - $skipped)
    let status = (if $failed == 0 { "pass" } else { "fail" })
    if ($env.OCMTS_TEST_JSON? == "1") {
        let failure_labels = ($failure_entries | each {|f| $f | str replace "FAIL: " ""})
        let skip_labels = ($skipped_entries | each {|s| $s | str replace "SKIP: " ""})
        print ({
            suite: $suite_name,
            path: $suite_path,
            status: $status,
            total: $total,
            passed: $passed,
            failed: $failed,
            skipped: $skipped,
            failures: $failure_labels,
            skips: $skip_labels,
        } | to json --raw)
        if ($failure_entries | is-not-empty) { exit 1 } else { exit 0 }
    } else {
        let skip_note = (if $skipped > 0 { $", ($skipped) skipped" } else { "" })
        print $"\n=== ($suite_name): ($passed)/($total) passed($skip_note) ==="
        if ($skipped_entries | is-not-empty) {
            print "Skipped:"
            for s in $skipped_entries { print $"  ($s)" }
        }
        if ($failure_entries | is-not-empty) {
            print "Failures:"
            for f in $failure_entries { print $"  ($f)" }
            exit 1
        }
        print "All tests passed."
        exit 0
    }
}
