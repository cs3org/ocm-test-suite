# Test domain: test execution against an already-up stack.

use ../../lib/cell.nu [compute-cell]
use ../../lib/artifacts-init.nu [read-last-execution-id]
use ../../lib/compose-validate.nu [validate-compose-strict]
use ../../lib/execution-id.nu [execution-artifacts-path]
use ../../lib/run-metadata.nu [write-terminal-run write-compact-result utc-now]
use ../../lib/domain/core/ocmts-root.nu [get-ocmts-root]

# Returns true if docker compose reports the platform service as running for the
# given stack. Uses the captured active file list so no /tmp dependency.
def stack-platform-running [f_args: list<string>, stack_id: string] {
    let result = (try {
        ^docker compose ...$f_args -p $stack_id ps --status running --services | complete
    } catch {
        {exit_code: 1, stdout: "", stderr: ""}
    })
    if $result.exit_code != 0 {
        false
    } else {
        let running = ($result.stdout | lines | each {|l| $l | str trim} | where {|l| not ($l | is-empty)})
        "platform" in $running
    }
}

def main [] {
    print "Usage: nu scripts/ocmts.nu test <verb> [flags]"
    print ""
    print "Verbs:"
    print "  run   Run Cypress tests headless against an already-up stack"
    print ""
    print "Notes:"
    print "  --record is not accepted here: the runner-ci.yml overlay is"
    print "  pre-rendered by 'services up'. To record video, pass --record"
    print "  to 'services up run' or 'services up' instead."
}

def "main run" [
    --scenario: string,
    --sender-platform: string,
    --sender-version: string,
    --browser: string = "chrome",
    --execution-id: string = "",
] {
    let root = get-ocmts-root
    let cell = (compute-cell $scenario $sender_platform $sender_version $browser)
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
    # For passed/failed reruns, verify the platform service is actually running.
    if ($cur_status in ["passed" "failed"]) {
        let active_files_path = ($art_compose | path join "active-files.txt")
        if not ($active_files_path | path exists) {
            error make {msg: $"Cannot rerun tests: execution ($exec_id) has status '($cur_status)' but active-files marker not found. Use 'services up' for a new run."}
        }
        let check_files = (open --raw $active_files_path | lines | where {|l| not ($l | is-empty)})
        let check_f_args = ($check_files | each {|f| ["-f" $f]} | flatten)
        if not (stack-platform-running $check_f_args $stack_id) {
            error make {msg: $"Cannot rerun tests: execution ($exec_id) has status '($cur_status)' but platform service is not running. Run 'services down' then 'services up' for a new run."}
        }
    }
    let started_at = ($prev_run.started_at? | default (utc-now))

    # Read images from cell.json (written by setup-run-context).
    let cell_meta = (open ($artifacts_base | path join "meta/cell.json"))
    let images = ($cell_meta.images? | default null)

    # Use the durable artifact copies so this command works even after /tmp is cleared.
    let run_files = [
        $base_yml
        ($inputs | path join "exec.yml")
        ($inputs | path join "platform.yml")
        ($inputs | path join "helpers.yml")
        ($inputs | path join "runner-ci.yml")
    ]
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
    # Empty catch so output streams live; exit code captured via LAST_EXIT_CODE.
    try { ^docker compose ...$f_args -p $stack_id run --rm cypress } catch { }
    let cypress_exit = $env.LAST_EXIT_CODE

    let finished_at = (utc-now)
    let status = if $cypress_exit == 0 { "passed" } else { "failed" }

    (write-terminal-run $artifacts_base $exec_id $cell.cell_id
        $cell.artifact_name $started_at $finished_at $status $cypress_exit $stack_id
        $images)
    (write-compact-result $artifacts_base $exec_id
        $cell.cell_id $status $cypress_exit $finished_at)

    exit $cypress_exit
}
