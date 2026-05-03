# Run Cypress tests headless against an already-up stack.

use ../../lib/matrix/cell.nu [compute-cell validate-cell-rules assert-scenario-enabled]
use ../../lib/artifacts/init.nu [read-last-execution-id]
use ../../lib/run/execution-id.nu [execution-artifacts-path]
use ../../lib/compose/validate.nu [validate-compose-strict]
use ../../lib/run/metadata.nu [write-terminal-outcome]
use ../../lib/time/utc.nu [utc-now]
use ../../lib/publish/envelope.nu [publish-envelope-safe emit-publish-envelope]
use ../../lib/domain/core/ocmts-root.nu [get-ocmts-root]
use ../../lib/services/cypress-run.nu [run-cypress-ci]
use ../../lib/services/compose-files.nu [
    build-f-args
    read-compose-files-from-manifest
]
use ../../lib/services/postrun-artifacts.nu [normalize-cypress-video]
use ../../lib/run/finalize.nu [finalize-run]

# Returns true if docker compose reports the primary platform service as running.
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

def main [
    --scenario: string,
    --sender-platform: string,
    --sender-version: string,
    --receiver-platform: string = "",
    --receiver-version: string = "",
    --browser: string = "chrome",
    --execution-id: string = "",
    --verbose,     # Show all docker compose output; default is quiet mode
] {
    let root = get-ocmts-root
    assert-scenario-enabled $scenario
    let flow_id = (validate-cell-rules
        $scenario $sender_platform $sender_version $browser
        $receiver_platform $receiver_version)
    let cell = (compute-cell
        $scenario $sender_platform $sender_version $browser
        $receiver_platform $receiver_version $flow_id)
    let exec_id = if ($execution_id | is-empty) {
        read-last-execution-id $cell.flow_id $cell.pair
    } else {
        $execution_id
    }
    let artifacts_base = (execution-artifacts-path $root $cell.flow_id $cell.pair $exec_id)
    let art_compose = ($artifacts_base | path join "compose")
    let base_yml = ($root | path join "config/compose/base.yml")

    let run_meta_path = ($artifacts_base | path join "meta/run.json")
    if not ($run_meta_path | path exists) {
        error make {msg: $"No run.json found for execution_id=($exec_id). Run 'services up' first."}
    }
    let prev_run = (open $run_meta_path)
    let stack_id = ($prev_run.stack_id? | default "")
    if ($stack_id | is-empty) {
        error make {msg: $"meta/run.json has no stack_id for execution_id=($exec_id)."}
    }
    let cur_status = ($prev_run.status? | default "")
    let terminal_statuses = ["stopped" "infra-failed" "cleanup-failed" "down-failed"]
    let allowed_statuses = ["active" "open" "passed" "failed"]
    if $cur_status in $terminal_statuses {
        error make {msg: $"Cannot run tests: execution ($exec_id) has terminal status '($cur_status)'. Start a new run with 'services up'."}
    } else if not ($cur_status in $allowed_statuses) {
        error make {msg: $"Cannot run tests: execution ($exec_id) has unexpected status '($cur_status)'."}
    }
    if ($cur_status in ["passed" "failed"]) {
        let check_files = (read-compose-files-from-manifest $artifacts_base $root)
        let check_f_args = (build-f-args $check_files)
        if not (stack-platform-running $check_f_args $stack_id $cell.is_two_party) {
            error make {msg: $"Cannot rerun tests: execution ($exec_id) has status '($cur_status)' but platform service is not running. Run 'services down' then 'services up' for a new run."}
        }
    }
    let started_at = ($prev_run.started_at? | default (utc-now))

    let cell_meta = (open ($artifacts_base | path join "meta/cell.json"))
    let images = ($cell_meta.images? | default null)

    let base_files = (read-compose-files-from-manifest $artifacts_base $root)
    let run_files = ($base_files | append ($root | path join "config/compose/runner-ci.yml"))
    let f_args = (build-f-args $run_files)

    # Validate runner-ci file set strictly before running Cypress.
    try {
        (validate-compose-strict $run_files $stack_id
            ($art_compose | path join "compose.resolved.run.yml"))
    } catch {|e|
        let finished_at = (utc-now)
        (write-terminal-outcome $artifacts_base $exec_id $cell.cell_id
            $cell.artifact_name $started_at $finished_at "infra-failed" 1 $stack_id
            $images --phase "compose-validate-runner-ci" --fail-error $e.msg)
        publish-envelope-safe $artifacts_base
        error make {msg: $"Compose runner-ci validation failed: ($e.msg)"}
    }

    print $"Running tests for ($cell.cell_id) [execution_id=($exec_id)]..."
    let cy = (run-cypress-ci $artifacts_base $f_args $stack_id $verbose)
    let cypress_exit = $cy.exit_code

    let finished_at = (utc-now)
    let final_exit = (finalize-run $artifacts_base $exec_id
        $cell.cell_id $cell.artifact_name
        $started_at $finished_at $stack_id $cypress_exit "after-cypress"
        $images)
    try {
        normalize-cypress-video $artifacts_base $cell.cell_id
    } catch {|e|
        print $"WARNING: video normalization error: ($e.msg)"
    }
    emit-publish-envelope $artifacts_base

    exit $final_exit
}
