# Bring up services, run tests headless, collect artifacts, tear down.

use ../../lib/compose/validate.nu [validate-compose-strict]
use ../../lib/run/metadata.nu [write-terminal-outcome]
use ../../lib/time/utc.nu [utc-now]
use ../../lib/mitm/peers.nu [write-mitm-peers]
use ../../lib/services/cypress-run.nu [run-cypress-ci]
use ../../lib/services/postrun-artifacts.nu [collect-run-artifacts]
use ../../lib/services/context.nu [setup-run-context]
use ../../lib/services/compose-files.nu [
    build-f-args write-compose-manifest
]
use ../../lib/services/lifecycle.nu [
    cleanup-temp
    ensure-network-gone
    cleanup-down
    overwrite-cleanup-failed
    do-compose-up
    do-compose-down
]
use ../../lib/services/infra-fail.nu [with-infra-fail-cleanup]
use ../../lib/compose/logs.nu [collect-service-logs]
use ../../lib/publish/envelope.nu [publish-envelope-safe emit-publish-envelope]
use ../../lib/suite/index.nu [record-suite-run-safe]
use ../../lib/run/finalize.nu [finalize-run]
use ../../lib/images/cell-images.nu [emit-cell-images]

def main [
    --flow: string,
    --sender-platform: string,
    --sender-version: string,
    --receiver-platform: string = "",
    --receiver-version: string = "",
    --browser: string = "chrome",
    --no-video,
    --preserve-temp,
    --keep-up,
    --verbose,
    --suite-id: string = "",
    --suite-kind: string = "single",
    --execution-id: string = "",
] {
    let ctx = (setup-run-context
        $flow $sender_platform $sender_version $browser (not $no_video)
        $receiver_platform $receiver_version
        --suite-id $suite_id --suite-kind $suite_kind
        --execution-id $execution_id)
    let env_file = $ctx.env_file
    let env_args = if ($env_file | is-empty) { [] } else { ["--env-file" $env_file] }
    let base_files = ([$ctx.base_yml] | append (
        $ctx.base_overlay_fnames | each {|f| $ctx.compose_d | path join $f}
    ))
    let f_args_base = (build-f-args $base_files)
    let run_files = ($base_files | append ($ctx.compose_d | path join "runner-ci.yml"))
    let f_args_run = (build-f-args $run_files)
    (write-compose-manifest $ctx.artifacts_base $ctx.stack_id
        $ctx.base_overlay_fnames "" ["compose.resolved.yml"])

    # Step 1: validate base file set strictly before touching Docker.
    let suite_hook_base = if $ctx.suite_kind == "suite" {
        {|r| (record-suite-run-safe $ctx.suite_id $ctx.cell.flow_id $ctx.cell.pair
            $ctx.execution_id $ctx.cell.cell_id $ctx.cell.artifact_name
            $r.status $r.exit_code $ctx.started_at (utc-now))}
    } else { null }
    (with-infra-fail-cleanup $ctx "compose-validate-base" {
        (validate-compose-strict $base_files $ctx.stack_id
            ($ctx.artifacts_base | path join "compose" "compose.resolved.yml")
            $env_file)
    } --preserve-temp=$preserve_temp --suite-record $suite_hook_base)

    # Bring up platform services; quiet by default, verbose with --verbose.
    let wait_services = if $ctx.is_two_party { ["sender" "receiver" "mitm"] } else { [] }
    if not $verbose { print "Starting services..." }
    let up_err = (do-compose-up $f_args_base $ctx.stack_id $wait_services $verbose $env_file)
    if $up_err != null {
        let finished_at = (utc-now)
        let up_exit = $up_err.exit_code
        (write-terminal-outcome $ctx.artifacts_base $ctx.execution_id
            $ctx.cell.cell_id $ctx.cell.artifact_name
            $ctx.started_at $finished_at "infra-failed" $up_exit $ctx.stack_id
            $ctx.images --phase "platform-up" --fail-error $up_err.msg
            --suite-id $ctx.suite_id --suite-kind $ctx.suite_kind)
        # Best-effort: collect container logs before teardown so infra failures are diagnosable.
        try {
            collect-service-logs $ctx.artifacts_base $ctx.stack_id $base_files []
        } catch {|log_err|
            print $"WARNING: log collection failed after compose up failure: ($log_err.msg)"
        }
        if not $keep_up {
            let down_fail = (try { cleanup-down $base_files $ctx.stack_id $ctx.artifacts_base $env_file; null } catch {|ce| $ce.msg})
            if $down_fail != null {
                overwrite-cleanup-failed $ctx $preserve_temp $down_fail $"platform-up failed: ($up_err.msg)"
            }
        }
        if $ctx.suite_kind == "suite" {
            (record-suite-run-safe $ctx.suite_id $ctx.cell.flow_id $ctx.cell.pair
                $ctx.execution_id $ctx.cell.cell_id $ctx.cell.artifact_name
                "infra-failed" $up_exit $ctx.started_at $finished_at)
        }
        publish-envelope-safe $ctx.artifacts_base
        cleanup-temp $ctx.execution_id $preserve_temp
        error make {msg: $"docker compose up platform failed: ($up_err.msg)"}
    }

    emit-cell-images $ctx.artifacts_base $ctx.stack_id $ctx.images $ctx.is_two_party

    # Write peers.json before Cypress so it exists even if tests fail.
    if $ctx.is_two_party {
        try {
            write-mitm-peers $ctx.artifacts_base $ctx.stack_id $ctx.cell
        } catch {|e|
            print $"WARNING: write-mitm-peers failed: ($e.msg)"
        }
    }

    # Step 2: validate runner-ci file set strictly before running Cypress.
    let suite_hook_runner = if $ctx.suite_kind == "suite" {
        {|r| (record-suite-run-safe $ctx.suite_id $ctx.cell.flow_id $ctx.cell.pair
            $ctx.execution_id $ctx.cell.cell_id $ctx.cell.artifact_name
            $r.status $r.exit_code $ctx.started_at (utc-now))}
    } else { null }
    (with-infra-fail-cleanup $ctx "compose-validate-runner-ci" {
        (validate-compose-strict $run_files $ctx.stack_id
            ($ctx.artifacts_base | path join "compose" "compose.resolved.run.yml")
            $env_file)
    } --preserve-temp=$preserve_temp
        --base-files (if not $keep_up { $base_files } else { [] })
        --env-file $env_file
        --suite-record $suite_hook_runner)
    (write-compose-manifest $ctx.artifacts_base $ctx.stack_id
        $ctx.base_overlay_fnames "runner-ci.yml"
        ["compose.resolved.yml" "compose.resolved.run.yml" "compose.resolved.down.yml"])

    print $"Running tests for ($ctx.cell.cell_id) [execution_id=($ctx.execution_id)]..."
    let cy = (run-cypress-ci $ctx.artifacts_base $f_args_run $ctx.stack_id $verbose $env_file)
    let cypress_exit = $cy.exit_code
    let cypress_status = if $cypress_exit == 0 { "passed" } else { "failed" }

    collect-run-artifacts $ctx.artifacts_base $ctx.stack_id $run_files $ctx.is_two_party

    mut down_err = null
    if not $keep_up {
        print "Tearing down services..."
        let down_files = $base_files
        let f_args_down = (build-f-args $down_files)
        let down_validate_err = (try {
            (validate-compose-strict $down_files $ctx.stack_id
                ($ctx.artifacts_base | path join "compose" "compose.resolved.down.yml")
                $env_file)
            null
        } catch {|ve|
            $ve.msg
        })
        $down_err = if $down_validate_err != null {
            $"compose down validation failed: ($down_validate_err)"
        } else {
            let dc_err = (do-compose-down $f_args_down $ctx.stack_id $verbose $env_file)
            if $dc_err != null {
                $dc_err
            } else {
                try { ensure-network-gone $ctx.stack_id; null } catch {|e| $e.msg}
            }
        }
    }

    let finished_at = (utc-now)
    if $down_err != null {
        let down_fail_msg = $"cleanup/down failed: ($down_err)"
        (write-terminal-outcome $ctx.artifacts_base $ctx.execution_id
            $ctx.cell.cell_id $ctx.cell.artifact_name
            $ctx.started_at $finished_at "cleanup-failed" 1 $ctx.stack_id
            $ctx.images --phase "compose-down"
            --fail-error $"($down_fail_msg) [cypress: status=($cypress_status) exit=($cypress_exit)]"
            --suite-id $ctx.suite_id --suite-kind $ctx.suite_kind)
        if $ctx.suite_kind == "suite" {
            (record-suite-run-safe $ctx.suite_id $ctx.cell.flow_id $ctx.cell.pair
                $ctx.execution_id $ctx.cell.cell_id $ctx.cell.artifact_name
                "cleanup-failed" 1 $ctx.started_at $finished_at)
        }
        publish-envelope-safe $ctx.artifacts_base
        cleanup-temp $ctx.execution_id $preserve_temp
        error make {msg: $down_fail_msg}
    }

    let final_stage = if $keep_up { "after-cypress" } else { "after-down" }
    let final_exit = (finalize-run $ctx.artifacts_base $ctx.execution_id
        $ctx.cell.cell_id $ctx.cell.artifact_name
        $ctx.started_at $finished_at $ctx.stack_id $cypress_exit $final_stage
        $ctx.images
        --suite-id $ctx.suite_id --suite-kind $ctx.suite_kind)
    let final_status = if $final_exit == 0 { "passed" } else { "failed" }
    emit-publish-envelope $ctx.artifacts_base
    if $ctx.suite_kind == "suite" {
        (record-suite-run-safe $ctx.suite_id $ctx.cell.flow_id $ctx.cell.pair
            $ctx.execution_id $ctx.cell.cell_id $ctx.cell.artifact_name
            $final_status $final_exit $ctx.started_at $finished_at)
    }
    cleanup-temp $ctx.execution_id $preserve_temp
    print $"Done. status=($final_status) execution_id=($ctx.execution_id)"
    print $"Artifacts: ($ctx.artifacts_base)"
    exit $final_exit
}
