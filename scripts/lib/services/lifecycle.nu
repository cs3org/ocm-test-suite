# Docker compose lifecycle helpers: cleanup, up, down, network management.

use ./compose-files.nu [build-f-args]
use ../compose-validate.nu [validate-compose-strict]
use ../execution-id.nu [execution-temp-path]
use ../run-metadata.nu [write-terminal-run write-compact-result utc-now]

# Remove /tmp/ocmts/<execution_id> when not preserving temp.
export def cleanup-temp [execution_id: string, preserve_temp: bool] {
    if $preserve_temp { return }
    if ($execution_id | is-empty) { return }
    let tmp_d = (execution-temp-path $execution_id)
    try {
        if ($tmp_d | path exists) { rm -rf $tmp_d }
    } catch {|e|
        print $"WARNING: temp cleanup failed for ($tmp_d): ($e.msg)"
    }
}

# After compose down, verify the project network (named by stack_id) is gone.
# Attempts removal once; if that fails, waits 2s and retries once more.
export def ensure-network-gone [stack_id: string] {
    let inspect = (try {
        ^docker network inspect $stack_id | complete
    } catch {
        {exit_code: 1, stdout: "", stderr: ""}
    })
    if $inspect.exit_code != 0 { return }

    print $"WARNING: network ($stack_id) still present after compose down; removing..."
    let rm1 = (try {
        ^docker network rm $stack_id | complete
    } catch {
        {exit_code: 1, stdout: "", stderr: ""}
    })
    if $rm1.exit_code == 0 { return }

    sleep 2sec
    let rm2 = (try {
        ^docker network rm $stack_id | complete
    } catch {
        {exit_code: 1, stdout: "", stderr: ""}
    })
    if $rm2.exit_code != 0 {
        let err = ($rm2.stderr | str trim)
        error make {msg: $"network ($stack_id) still present after compose down; removal failed: ($err)"}
    }
}

# Validate down file set then run compose down (always verbose; used in error paths).
# Throws on validation failure or on compose down failure.
export def cleanup-down [
    files: list<string>,
    stack_id: string,
    artifacts_base: string = "",
] {
    let resolved_path = if ($artifacts_base | is-empty) {
        ""
    } else {
        $artifacts_base | path join "compose" "compose.resolved.down.yml"
    }
    validate-compose-strict $files $stack_id $resolved_path
    let f_args = (build-f-args $files)
    ^docker compose ...$f_args -p $stack_id down --volumes
    ensure-network-gone $stack_id
}

# Overwrite run/result metadata to cleanup-failed when a down attempt fails
# after an earlier failure. Always throws with the combined error message.
export def overwrite-cleanup-failed [
    ctx: record,
    preserve_temp: bool,
    down_fail: string,
    original_err: string,
] {
    let cf_at = (utc-now)
    let combined = $"cleanup/down failed: ($down_fail) [($original_err)]"
    (write-terminal-run $ctx.artifacts_base $ctx.execution_id
        $ctx.cell.cell_id $ctx.cell.artifact_name
        $ctx.started_at $cf_at "cleanup-failed" 1 $ctx.stack_id
        $ctx.images --phase "compose-down" --fail-error $combined)
    (write-compact-result $ctx.artifacts_base $ctx.execution_id
        $ctx.cell.cell_id "cleanup-failed" 1 $cf_at)
    cleanup-temp $ctx.execution_id $preserve_temp
    error make {msg: $combined}
}

# Try to bring up compose services; returns null on success or {exit_code, msg} on failure.
# Quiet mode buffers output and exposes stderr only on failure.
export def do-compose-up [
    f_args: list<string>,
    stack_id: string,
    wait_services: list<string>,
    verbose: bool,
] {
    if $verbose {
        try {
            ^docker compose ...$f_args -p $stack_id up -d --wait ...$wait_services
            null
        } catch {|e|
            {exit_code: ($env.LAST_EXIT_CODE? | default 1), msg: $e.msg}
        }
    } else {
        let r = (^docker compose ...$f_args -p $stack_id up -d --wait ...$wait_services | complete)
        if $r.exit_code != 0 {
            let msg = if ($r.stderr | str trim | is-empty) {
                $"docker compose up exited ($r.exit_code)"
            } else {
                $r.stderr | str trim
            }
            {exit_code: $r.exit_code, msg: $msg}
        } else {
            null
        }
    }
}

# Try to run compose down; returns null on success or an error string on failure.
# Quiet mode buffers output.
export def do-compose-down [
    f_args: list<string>,
    stack_id: string,
    verbose: bool,
] {
    if $verbose {
        try {
            ^docker compose ...$f_args -p $stack_id down --volumes
            null
        } catch {|e|
            $e.msg
        }
    } else {
        let r = (^docker compose ...$f_args -p $stack_id down --volumes | complete)
        if $r.exit_code != 0 {
            let msg = if ($r.stderr | str trim | is-empty) {
                $"compose down exited ($r.exit_code)"
            } else {
                $r.stderr | str trim
            }
            $msg
        } else {
            null
        }
    }
}
