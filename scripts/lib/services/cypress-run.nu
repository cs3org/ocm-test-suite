# Shared Cypress CI runner helper with verbosity support.
# Runs cypress via docker compose with tee to cypress-run.log.
# Quiet mode filters docker compose container/network noise while still
# passing Cypress output to the terminal.

# Run cypress headless via docker compose and tee output to the run log.
# Quiet mode prints a progress line and filters compose noise from stdout;
# full output is always captured in the log file.
# Returns {exit_code: int, log_path: string}.
export def run-cypress-ci [
    artifacts_base: string,
    f_args: list<string>,
    stack_id: string,
    verbose: bool,
] {
    let logs_dir = ($artifacts_base | path join "docker" "logs")
    if not ($logs_dir | path exists) {
        try { mkdir $logs_dir } catch {|e| print $"WARNING: could not create log dir: ($e.msg)" }
    }
    let cypress_log = ($logs_dir | path join "cypress-run.log")

    if not $verbose {
        print $"Running cypress... \(log: ($cypress_log)\)"
    }

    # Verbose: streams all output including compose noise.
    # Quiet: filters Container/Network progress lines from terminal stdout but
    # captures everything in the log. PIPESTATUS[0] preserves docker exit code.
    # || true prevents grep exit 1 (no matches) from being treated as failure.
    let tee_script = if $verbose {
        'set -o pipefail; log="$1"; shift; "$@" 2>&1 | tee "$log"; exit ${PIPESTATUS[0]}'
    } else {
        'set -o pipefail; log="$1"; shift; "$@" 2>&1 | tee "$log" | { grep -Ev "^(\s*(Container|Network)\s+ocmts--)" || true; }; exit ${PIPESTATUS[0]}'
    }
    try {
        ^bash -c $tee_script -- $cypress_log docker compose ...$f_args -p $stack_id run --rm cypress
    } catch { }
    let cypress_exit = $env.LAST_EXIT_CODE

    # Verify cypress log was written; warn if missing or empty.
    try {
        let log_missing_or_empty = if not ($cypress_log | path exists) {
            true
        } else {
            let log_size = (ls $cypress_log | first | get size)
            $log_size == 0b
        }
        if $log_missing_or_empty {
            let warn_msg = $"WARNING: cypress-run.log missing or empty: ($cypress_log)"
            print $warn_msg
            try { mkdir ($artifacts_base | path join "meta") } catch { }
            try {
                $warn_msg | save --force ($artifacts_base | path join "meta/cypress-run-warning.txt")
            } catch {|se| print $"WARNING: could not write cypress-run-warning.txt: ($se.msg)" }
        }
    } catch {|e|
        print $"WARNING: could not check cypress-run.log: ($e.msg)"
    }

    {exit_code: $cypress_exit, log_path: $cypress_log}
}
