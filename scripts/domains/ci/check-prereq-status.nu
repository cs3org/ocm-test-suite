# Check prerequisite artifact status for a CI run cell.
# Prints the first failure reason string, or nothing if all prerequisites passed.
# Mirrors the bash "Check prerequisite status" step in ci-run-cell.yml.tpl.

use ../../lib/ci/prereq-status.nu [eval-prereq-status]

def main [
    --deps: string = "",           # comma-separated list of prerequisite cell IDs
    --prereqs-root: string = "prereqs",  # dir containing per-dep artifact subdirs
] {
    let dep_list = if ($deps | is-empty) {
        []
    } else {
        $deps | split row ","
    }
    let reason = (eval-prereq-status $dep_list $prereqs_root)
    if not ($reason | is-empty) {
        print $reason
    }
}
