# Run internal Nushell unit tests for the ocmts CLI.
# Default: all NON-manual suites, combined JSON output.
# NOT for Cypress E2E tests; those are `ocmts test cypress run/suite`.

use ../../lib/domain/core/ocmts-root.nu [get-ocmts-root]

# Returns suite IDs relative to tests_dir, e.g. "ci/planner".
def discover-suites [tests_dir: string, include_manual: bool]: nothing -> list<string> {
    glob $"($tests_dir)/**/*.nu"
    | where {|p| ($p | path basename) != "run-all.nu"}
    | where {|p|
        if $include_manual {
            true
        } else {
            not ($p | str contains "/manual/")
        }
    }
    | sort
    | each {|p| $p | path relative-to $tests_dir | str replace ".nu" ""}
}

def is-manual-suite [suite_id: string]: nothing -> bool {
    $suite_id | str contains "integration/manual/"
}

# Runs suites with OCMTS_TEST_JSON=1, prints combined JSON, returns failed count.
def run-suites-json [tests_dir: string, suite_ids: list<string>]: nothing -> int {
    mut results = []
    for suite_id in $suite_ids {
        let suite_file = ($tests_dir | path join $"($suite_id).nu")
        let r = (with-env { OCMTS_TEST_JSON: "1" } { ^nu $suite_file | complete })
        let nonempty_lines = ($r.stdout | lines | where {|l| not ($l | str trim | is-empty)})
        let parsed = if ($nonempty_lines | is-empty) {
            let nonempty_err = ($r.stderr | lines | where {|l| not ($l | str trim | is-empty)})
            let tail = if ($nonempty_err | is-empty) { "" } else { $nonempty_err | last }
            {suite: $suite_id, path: $suite_file, status: "fail", total: 0, passed: 0, failed: 1,
                failures: [$"runner crashed: ($tail)"]}
        } else {
            let json_line = ($nonempty_lines | last)
            try { $json_line | from json } catch {
                let nonempty_err = ($r.stderr | lines | where {|l| not ($l | str trim | is-empty)})
                let tail = if ($nonempty_err | is-empty) { "" } else { $nonempty_err | last }
                {suite: $suite_id, path: $suite_file, status: "fail", total: 0, passed: 0, failed: 1,
                    failures: [$"runner crashed: ($tail)"]}
            }
        }
        $results = ($results | append $parsed)
    }

    let suite_count = ($results | length)
    let total = ($results | each {|r| $r.total} | math sum)
    let passed = ($results | each {|r| $r.passed} | math sum)
    let failed = ($results | each {|r| $r.failed} | math sum)
    let status = (if $failed == 0 { "pass" } else { "fail" })

    print ({
        suites: $suite_count,
        total: $total,
        passed: $passed,
        failed: $failed,
        status: $status,
        results: $results,
    } | to json --raw)

    $failed
}

# Streams each suite's output to terminal, returns 1 if any suite failed.
def run-suites-human [tests_dir: string, suite_ids: list<string>]: nothing -> int {
    mut any_failed = false
    for suite_id in $suite_ids {
        let suite_file = ($tests_dir | path join $"($suite_id).nu")
        print --stderr $"--- suite: ($suite_id) ---"
        ^nu $suite_file
        if $env.LAST_EXIT_CODE != 0 {
            $any_failed = true
        }
    }
    if $any_failed { 1 } else { 0 }
}

def main [
    --suite: string = ""   # Run one suite by area/topic (e.g. ci/planner)
    --suites: string = ""  # Run multiple suites, comma-separated IDs
    --list                 # List available unit suites (non-manual by default)
    --include-manual       # Include integration/manual/ suites in --list, or allow them in --suite/--suites
    --human                # Human-friendly streaming output; applies to all run modes
] {
    let root = (get-ocmts-root)
    let tests_dir = ($root | path join "scripts" "tests")

    if $list {
        let suite_ids = (discover-suites $tests_dir $include_manual)
        for s in $suite_ids {
            print $s
        }
        return
    }

    if not ($suite | is-empty) {
        let suite_file = ($tests_dir | path join $"($suite).nu")
        if not ($suite_file | path exists) {
            print --stderr $"Error: suite not found: ($suite)"
            print --stderr ""
            print --stderr "Available suites (run --list to see all):"
            let available = (discover-suites $tests_dir true)
            for s in $available {
                print --stderr $"  ($s)"
            }
            exit 1
        }
        if (is-manual-suite $suite) and not $include_manual {
            print --stderr $"Error: '($suite)' is a manual suite. Pass --include-manual to run it."
            exit 1
        }
        print --stderr $"Running suite: ($suite)"
        if $human {
            ^nu $suite_file
        } else {
            with-env { OCMTS_TEST_JSON: "1" } { ^nu $suite_file }
        }
        exit $env.LAST_EXIT_CODE
    }

    if not ($suites | is-empty) {
        let suite_ids = (
            $suites
            | split row ","
            | each {|s| $s | str trim}
            | where {|s| not ($s | is-empty)}
        )
        for suite_id in $suite_ids {
            let suite_file = ($tests_dir | path join $"($suite_id).nu")
            if not ($suite_file | path exists) {
                print --stderr $"Error: suite not found: ($suite_id)"
                exit 1
            }
            if (is-manual-suite $suite_id) and not $include_manual {
                print --stderr $"Error: '($suite_id)' is a manual suite. Pass --include-manual to run it."
                exit 1
            }
        }
        let failed_count = if $human {
            run-suites-human $tests_dir $suite_ids
        } else {
            run-suites-json $tests_dir $suite_ids
        }
        if $failed_count > 0 { exit 1 }
        return
    }

    # Default: all non-manual suites
    let suite_ids = (discover-suites $tests_dir false)
    print --stderr "Running all unit suites..."
    let failed_count = if $human {
        run-suites-human $tests_dir $suite_ids
    } else {
        run-suites-json $tests_dir $suite_ids
    }
    if $failed_count > 0 { exit 1 }
}
