# Shared infra-failure handling helper.
# Extracts the repeated try/catch pattern in services/up.nu and friends:
# run an action, and on error write an infra-failed terminal outcome,
# emit the publish envelope, clean up, and re-throw.

use ../run/metadata.nu [write-terminal-outcome]
use ../time/utc.nu [utc-now]
use ../publish/envelope.nu [publish-envelope-safe]
use ../compose/logs.nu [collect-service-logs]
use ./lifecycle.nu [cleanup-temp cleanup-down overwrite-cleanup-failed]

# Run `action` and return its result on success.
# On failure: writes an infra-failed terminal outcome, optionally invokes
# --suite-record closure with {status, exit_code} before publishing the
# envelope, cleans up temp dirs, and re-throws the error.
#
# ctx must have: artifacts_base, execution_id, cell.cell_id, cell.artifact_name,
#   started_at, stack_id, images, suite_id, suite_kind, execution_id.
# phase: label for the failure phase (e.g. "compose-validate-base", "platform-up").
# exit_code: positive failure code recorded when the failure is not an
#   external non-zero status (default 1). Missing, zero, and negative
#   LAST_EXIT_CODE values clamp to this code.
# suite-record: optional closure called with {status, exit_code} before publish.

# Keep a positive external status. Missing, zero, and negative values use the
# requested failure code so a later Nu error cannot record exit_code 0.
def clamp-infra-exit-code [requested: int, observed: any] {
    let fallback = if $requested > 0 { $requested } else { 1 }
    if $observed == null {
        return $fallback
    }
    let code = (try { $observed | into int } catch { return $fallback })
    if $code > 0 {
        $code
    } else {
        $fallback
    }
}

# External failures carry exit_code on the error record. A Nu validation
# error does not. Nushell 0.116 also sets LAST_EXIT_CODE to 1 for those
# errors; that 1 is not an external status, so the requested code applies.
# A positive LAST_EXIT_CODE other than that synthetic 1 is preserved.
def observed-infra-exit [err: record] {
    let from_err = ($err.exit_code? | default null)
    if $from_err != null {
        return $from_err
    }
    let msg = ($err.msg? | default "")
    if $msg == "External command had a non-zero exit code" {
        return ($env.LAST_EXIT_CODE? | default null)
    }
    let raw = ($env.LAST_EXIT_CODE? | default null)
    if $raw == null {
        return null
    }
    let code = (try { $raw | into int } catch { return null })
    if ($code == null) or ($code <= 0) or ($code == 1) {
        return null
    }
    $code
}

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
        # Read the status before any later command can replace LAST_EXIT_CODE.
        let eff_exit = (clamp-infra-exit-code $exit_code (observed-infra-exit $e))
        let finished_at = (utc-now)
        (write-terminal-outcome $ctx.artifacts_base $ctx.execution_id
            $ctx.cell.cell_id $ctx.cell.artifact_name
            $ctx.started_at $finished_at "infra-failed" $eff_exit $ctx.stack_id
            $ctx.images --phase $phase --fail-error $e.msg
            --suite-id $ctx.suite_id --suite-kind $ctx.suite_kind)
        if not ($base_files | is-empty) {
            try {
                collect-service-logs $ctx.artifacts_base $ctx.stack_id $base_files []
            } catch {|log_err|
                print $"WARNING: log collection failed after ($phase) failure: ($log_err.msg)"
            }
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
