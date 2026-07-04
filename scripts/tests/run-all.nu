# Run every test suite and emit a single combined JSON record on stdout.
# Each suite is invoked in a fresh child `nu` process with OCMTS_TEST_JSON=1.
# Exit code is 1 when any suite fails, 0 otherwise.
#
# Usage from repo root:
#   nu scripts/tests/run-all.nu
#   nu scripts/tests/run-all.nu | from json | get results

const SUITE_PATH = path self

def main [] {
    let tests_dir = ($SUITE_PATH | path dirname)
    let suites = (
        glob $"($tests_dir)/**/*.nu"
        | where {|p| ($p | path basename) != "run-all.nu"}
        # Only treat files that define a `main` entrypoint as suites. Shared
        # helper modules (e.g. ci/fixtures.nu) export fixtures but have no main.
        | where {|p| (open --raw $p | decode utf-8) =~ '(?m)^\s*(export )?def main\b'}
        # Exclude opt-in manual tests (e.g. heavy Docker/ffmpeg suites).
        | where {|p| not ($p | str contains "/manual/")}
        | sort
    )

    mut results = []
    for s in $suites {
        let r = (with-env { OCMTS_TEST_JSON: "1" } { ^nu $s | complete })
        let nonempty_lines = ($r.stdout | lines | where {|l| not ($l | str trim | is-empty)})
        let suite_name = ($s | path relative-to $tests_dir | str replace ".nu" "")
        let parsed = if ($nonempty_lines | is-empty) {
            let stderr_nonempty = ($r.stderr | lines | where {|l| not ($l | str trim | is-empty)})
            let stderr_tail = if ($stderr_nonempty | is-empty) { "" } else { $stderr_nonempty | last }
            {suite: $suite_name, path: $s, status: "fail", total: 0, passed: 0, failed: 1,
                failures: [$"runner crashed: ($stderr_tail)"]}
        } else {
            let json_line = ($nonempty_lines | last)
            try { $json_line | from json } catch {
                let stderr_nonempty = ($r.stderr | lines | where {|l| not ($l | str trim | is-empty)})
                let stderr_tail = if ($stderr_nonempty | is-empty) { "" } else { $stderr_nonempty | last }
                {suite: $suite_name, path: $s, status: "fail", total: 0, passed: 0, failed: 1,
                    failures: [$"runner crashed: ($stderr_tail)"]}
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

    if $failed > 0 { exit 1 }
}
