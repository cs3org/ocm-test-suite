# Test domain: test execution against an already-up stack.

use ../../lib/cell.nu [compute-cell]
use ../../lib/artifacts-init.nu [read-last-execution-id]
use ../../lib/compose-validate.nu [validate-compose-strict]
use ../../lib/execution-id.nu [execution-artifacts-path]
use ../../lib/run-metadata.nu [write-terminal-run write-compact-result utc-now]
use ../../lib/domain/core/ocmts-root.nu [get-ocmts-root]

# Returns true if docker compose reports the primary platform service as running.
# For one-party checks "platform"; for two-party checks "sender".
def stack-platform-running [f_args: list<string>, stack_id: string, is_two_party: bool] {
    let check_svc = if $is_two_party { "sender" } else { "platform" }
    let result = (try {
        ^docker compose ...$f_args -p $stack_id ps --status running --services | complete
    } catch {
        {exit_code: 1, stdout: "", stderr: ""}
    })
    if $result.exit_code != 0 {
        false
    } else {
        let running = ($result.stdout | lines | each {|l| $l | str trim} | where {|l| not ($l | is-empty)})
        $check_svc in $running
    }
}

def main [] {
    print "Usage: nu scripts/ocmts.nu test <verb> [flags]"
    print ""
    print "Verbs:"
    print "  run   Run Cypress tests headless against an already-up stack"
    print ""
    print "Notes:"
    print "  Video recording is enabled by default. To opt out, pass --no-video"
    print "  to 'services up', 'services up run', or 'services up open'."
    print "  'test run' reuses the runner-ci.yml overlay pre-rendered by"
    print "  'services up' / 'services up open', so the video setting is"
    print "  inherited from that prior step."
    print ""
    print "  'test run' does NOT tear down services after the test pass."
    print "  Platform service logs (platform container stdout/stderr) are"
    print "  NOT collected automatically by 'test run'. Only the Cypress"
    print "  container output is captured. If you need platform logs,"
    print "  run the following while the stack is still up:"
    print "    nu scripts/ocmts.nu artifacts collect --include-logs ..."
    print "  Platform log collection is otherwise tied to the teardown"
    print "  path ('services up run') which calls 'services down'."
}

def "main run" [
    --scenario: string,
    --sender-platform: string,
    --sender-version: string,
    --receiver-platform: string = "",
    --receiver-version: string = "",
    --browser: string = "chrome",
    --execution-id: string = "",
] {
    let root = get-ocmts-root
    let cell = (compute-cell
        $scenario $sender_platform $sender_version $browser
        $receiver_platform $receiver_version)
    let exec_id = if ($execution_id | is-empty) {
        read-last-execution-id $cell.artifact_name
    } else {
        $execution_id
    }
    let artifacts_base = (execution-artifacts-path $root $cell.artifact_name $exec_id)
    let art_compose = ($artifacts_base | path join "compose")
    let stack_id_file = ($art_compose | path join "stack_id.txt")
    if not ($stack_id_file | path exists) {
        error make {msg: $"No stack_id found for execution_id=($exec_id). Run 'services up' first."}
    }
    let stack_id = (open --raw $stack_id_file | str trim)
    let inputs = ($art_compose | path join "inputs")
    let base_yml = ($root | path join "config/compose/base.yml")

    # Read the prior run.json to preserve started_at and other context.
    let run_meta_path = ($artifacts_base | path join "meta/run.json")
    if not ($run_meta_path | path exists) {
        error make {msg: $"No run.json found for execution_id=($exec_id). Run 'services up' first."}
    }
    let prev_run = (open $run_meta_path)
    let cur_status = ($prev_run.status? | default "")
    let terminal_statuses = ["stopped" "infra-failed" "cleanup-failed" "down-failed"]
    let allowed_statuses = ["active" "open" "passed" "failed"]
    if $cur_status in $terminal_statuses {
        error make {msg: $"Cannot run tests: execution ($exec_id) has terminal status '($cur_status)'. Start a new run with 'services up'."}
    } else if not ($cur_status in $allowed_statuses) {
        error make {msg: $"Cannot run tests: execution ($exec_id) has unexpected status '($cur_status)'."}
    }
    # For passed/failed reruns, verify the primary service is actually running.
    if ($cur_status in ["passed" "failed"]) {
        let active_files_path = ($art_compose | path join "active-files.txt")
        if not ($active_files_path | path exists) {
            error make {msg: $"Cannot rerun tests: execution ($exec_id) has status '($cur_status)' but active-files marker not found. Use 'services up' for a new run."}
        }
        let check_files = (open --raw $active_files_path | lines | where {|l| not ($l | is-empty)})
        let check_f_args = ($check_files | each {|f| ["-f" $f]} | flatten)
        if not (stack-platform-running $check_f_args $stack_id $cell.is_two_party) {
            error make {msg: $"Cannot rerun tests: execution ($exec_id) has status '($cur_status)' but platform service is not running. Run 'services down' then 'services up' for a new run."}
        }
    }
    let started_at = ($prev_run.started_at? | default (utc-now))

    # Read images from cell.json (written by setup-run-context).
    let cell_meta = (open ($artifacts_base | path join "meta/cell.json"))
    let images = ($cell_meta.images? | default null)

    # Use the durable artifact copies so this command works even after /tmp is cleared.
    # Read base overlay fnames from active-files.txt if available, else fallback.
    let active_files_path = ($art_compose | path join "active-files.txt")
    let run_files = if ($active_files_path | path exists) {
        # Reconstruct run_files: active-files (base) + runner-ci overlay from inputs.
        let base_set = (open --raw $active_files_path | lines | where {|l| not ($l | is-empty)})
        # Check if runner-ci is already included (stored when it was active).
        let runner_ci_path = ($inputs | path join "runner-ci.yml")
        if ($runner_ci_path | path exists) and not ($runner_ci_path in $base_set) {
            $base_set | append $runner_ci_path
        } else {
            $base_set | append $runner_ci_path
        }
    } else {
        [
            $base_yml
            ($inputs | path join "exec.yml")
            ($inputs | path join "platform.yml")
            ($inputs | path join "helpers.yml")
            ($inputs | path join "runner-ci.yml")
        ]
    }
    let f_args = ($run_files | each {|f| ["-f" $f]} | flatten)

    # Validate runner-ci file set strictly before running Cypress.
    try {
        (validate-compose-strict $run_files $stack_id
            ($art_compose | path join "compose.resolved.run.yml"))
    } catch {|e|
        let finished_at = (utc-now)
        (write-terminal-run $artifacts_base $exec_id $cell.cell_id
            $cell.artifact_name $started_at $finished_at "infra-failed" 1 $stack_id
            $images --phase "compose-validate-runner-ci" --fail-error $e.msg)
        (write-compact-result $artifacts_base $exec_id
            $cell.cell_id "infra-failed" 1 $finished_at)
        error make {msg: $"Compose runner-ci validation failed: ($e.msg)"}
    }

    print $"Running tests for ($cell.cell_id) [execution_id=($exec_id)]..."
    let logs_dir = ($artifacts_base | path join "docker" "logs")
    if not ($logs_dir | path exists) {
        try { mkdir $logs_dir } catch {|e| print $"WARNING: could not create log dir: ($e.msg)" }
    }
    let cypress_log = ($logs_dir | path join "cypress-run.log")
    let tee_script = 'set -o pipefail; log="$1"; shift; "$@" 2>&1 | tee "$log"; exit ${PIPESTATUS[0]}'
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

    let finished_at = (utc-now)
    let status = if $cypress_exit == 0 { "passed" } else { "failed" }

    (write-terminal-run $artifacts_base $exec_id $cell.cell_id
        $cell.artifact_name $started_at $finished_at $status $cypress_exit $stack_id
        $images)
    (write-compact-result $artifacts_base $exec_id
        $cell.cell_id $status $cypress_exit $finished_at)

    exit $cypress_exit
}
