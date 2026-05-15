# Shared infra-failure handling helper.
# Extracts the repeated try/catch pattern in services/up.nu and friends:
# run an action, and on error write an infra-failed terminal outcome,
# emit the publish envelope, clean up, and re-throw.

use ../run/metadata.nu [write-terminal-outcome]
use ../time/utc.nu [utc-now]
use ../publish/envelope.nu [publish-envelope-safe]
use ./lifecycle.nu [cleanup-temp cleanup-down overwrite-cleanup-failed]

# Run `action` and return its result on success.
# On failure: writes an infra-failed terminal outcome, optionally invokes
# --suite-record closure with {status, exit_code} before publishing the
# envelope, cleans up temp dirs, and re-throws the error.
#
# ctx must have: artifacts_base, execution_id, cell.cell_id, cell.artifact_name,
#   started_at, stack_id, images, suite_id, suite_kind, execution_id.
# phase: label for the failure phase (e.g. "compose-validate-base", "platform-up").
# exit_code: override exit code for the infra-failed result (default 1).
# suite-record: optional closure called with {status, exit_code} before publish.
export def with-infra-fail-cleanup [
    ctx: record,
    phase: string,
    action: closure,
    --preserve-temp,
    --exit-code: int = 1,
    --base-files: list = [],
    --env-file: string = "",
    --suite-record: any = null,
] {
    try {
        do $action
    } catch {|e|
        let finished_at = (utc-now)
        let eff_exit = ($env.LAST_EXIT_CODE? | default $exit_code)
        (write-terminal-outcome $ctx.artifacts_base $ctx.execution_id
            $ctx.cell.cell_id $ctx.cell.artifact_name
            $ctx.started_at $finished_at "infra-failed" $eff_exit $ctx.stack_id
            $ctx.images --phase $phase --fail-error $e.msg
            --suite-id $ctx.suite_id --suite-kind $ctx.suite_kind)
        if not ($base_files | is-empty) {
            let down_fail = (try {
                cleanup-down $base_files $ctx.stack_id $ctx.artifacts_base $env_file
                null
            } catch {|ce| $ce.msg})
            if $down_fail != null {
                overwrite-cleanup-failed $ctx $preserve_temp $down_fail $"($phase) failed: ($e.msg)"
            }
        }
        if $suite_record != null {
            do $suite_record {status: "infra-failed", exit_code: $eff_exit}
        }
        publish-envelope-safe $ctx.artifacts_base
        cleanup-temp $ctx.execution_id $preserve_temp
        error make {msg: $"($phase) failed: ($e.msg)"}
    }
}
