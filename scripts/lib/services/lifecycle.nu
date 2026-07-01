# Docker compose lifecycle helpers: cleanup, up, down, network management.

use ./compose-files.nu [build-f-args]
use ../compose/validate.nu [validate-compose-strict]
use ../run/execution-id.nu [execution-temp-path]
use ../run/metadata.nu [write-terminal-outcome]
use ../time/utc.nu [utc-now]
use ../publish/envelope.nu [publish-envelope-safe]

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
    env_file: string = "",
] {
    let resolved_path = if ($artifacts_base | is-empty) {
        ""
    } else {
        $artifacts_base | path join "compose" "compose.resolved.down.yml"
    }
    validate-compose-strict $files $stack_id $resolved_path $env_file
    let f_args = (build-f-args $files)
    let env_args = if ($env_file | is-empty) { [] } else { ["--env-file" $env_file] }
    ^docker compose ...$env_args ...$f_args -p $stack_id down --volumes
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
    let suite_id = ($ctx.suite_id? | default "")
    let suite_kind = ($ctx.suite_kind? | default "")
    (write-terminal-outcome $ctx.artifacts_base $ctx.execution_id
        $ctx.cell.cell_id $ctx.cell.artifact_name
        $ctx.started_at $cf_at "cleanup-failed" 1 $ctx.stack_id
        $ctx.images --phase "compose-down" --fail-error $combined
        --suite-id $suite_id --suite-kind $suite_kind)
    publish-envelope-safe $ctx.artifacts_base
    cleanup-temp $ctx.execution_id $preserve_temp
    error make {msg: $combined}
}

# CI-tuned wrapper around `docker compose up -d --wait`.
#
# wait_services: compose service names to pass after `up -d --wait`. An empty
# list means no service targets - docker compose brings up and waits on the
# full project (required for one-party stacks such as CERNBox with many Reva
# microservices beyond `sender`).
#
# Behavior: quiet mode by default - output is buffered and stderr is surfaced
# only on failure. When verbose=true, output streams live to the terminal.
#
# Error contract: returns null on success, {exit_code: int, msg: string} on
# failure. Does NOT throw; the caller decides how to handle the error.
#
# Intended consumer: scripts/domains/services/up-run.nu (the CI run command).
#
# Operator-facing commands (services up, services up open) intentionally use
# direct `^docker compose ... up` calls instead: they want streaming output
# and natural throw-on-failure semantics that `^docker` provides. The
# structured-error contract here is a CI feature, not a generic plumbing layer.
export def do-compose-up [
    f_args: list<string>,
    stack_id: string,
    wait_services: list<string>,
    verbose: bool,
    env_file: string = "",
] {
    let env_args = if ($env_file | is-empty) { [] } else { ["--env-file" $env_file] }
    let up_cmd = {|extra|
        ^docker compose ...$env_args ...$f_args -p $stack_id up -d --wait ...$wait_services ...$extra
    }
    if $verbose {
        try {
            do $up_cmd []
            null
        } catch {|e|
            {exit_code: ($env.LAST_EXIT_CODE? | default 1), msg: $e.msg}
        }
    } else {
        let r = (do $up_cmd [] | complete)
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

# CI-tuned wrapper around `docker compose ... down --volumes`.
#
# Behavior: quiet mode by default - output is buffered. When verbose=true,
# output streams live to the terminal.
#
# Error contract: returns null on success, or an error string on failure.
# Does NOT throw; the caller decides how to handle the error.
#
# Intended consumer: scripts/domains/services/up-run.nu (the CI run command).
#
# Operator-facing commands use direct `^docker compose` calls wrapped in
# try/catch for natural throw-on-failure semantics; the structured-error
# contract here is a CI feature, not a generic plumbing layer.
export def do-compose-down [
    f_args: list<string>,
    stack_id: string,
    verbose: bool,
    env_file: string = "",
] {
    let env_args = if ($env_file | is-empty) { [] } else { ["--env-file" $env_file] }
    if $verbose {
        try {
            ^docker compose ...$env_args ...$f_args -p $stack_id down --volumes
            null
        } catch {|e|
            $e.msg
        }
    } else {
        let r = (^docker compose ...$env_args ...$f_args -p $stack_id down --volumes | complete)
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
