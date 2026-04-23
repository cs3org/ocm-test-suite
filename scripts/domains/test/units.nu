# Run internal Nushell unit tests for the ocmts CLI.
# Default: full aggregator (JSON output). Flags select one suite or list.
# NOT for Cypress E2E tests; those are `ocmts test cypress run/suite`.

use ../../lib/domain/core/ocmts-root.nu [get-ocmts-root]

def main [
    --suite: string = ""  # Run one suite by area/topic (e.g. ci/planner)
    --list                # List available unit suites and exit
    --human               # Human-friendly output; skips OCMTS_TEST_JSON=1
] {
    let root = (get-ocmts-root)
    let tests_dir = ($root | path join "scripts" "tests")

    if $list {
        glob $"($tests_dir)/**/*.nu"
        | where {|p| ($p | path basename) != "run-all.nu"}
        | each {|p|
            $p
            | path relative-to $tests_dir
            | str replace ".nu" ""
        }
        | sort
        | each {|s| print $s}
        return
    }

    if not ($suite | is-empty) {
        let suite_file = ($tests_dir | path join $"($suite).nu")
        if not ($suite_file | path exists) {
            print --stderr $"Error: suite not found: ($suite)"
            print --stderr ""
            print --stderr "Available suites (run with --list to see all):"
            glob $"($tests_dir)/**/*.nu"
            | where {|p| ($p | path basename) != "run-all.nu"}
            | each {|p| $p | path relative-to $tests_dir | str replace ".nu" ""}
            | sort
            | each {|s| print --stderr $"  ($s)"}
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

    # Default: delegate to run-all.nu
    let run_all = ($root | path join "scripts" "tests" "run-all.nu")
    print --stderr "Running all unit suites..."
    if $human {
        ^nu $run_all
    } else {
        ^nu $run_all
    }
    exit $env.LAST_EXIT_CODE
}
