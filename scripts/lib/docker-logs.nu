# Collect docker compose service logs and write them to artifacts docker/logs/.

# Collect logs for the given services using the active compose file set.
# Writes one file per service under artifacts_base/docker/logs/<service>.log.
# Returns {ok: bool, services: list<record>} where each service record is
# {service, ok, path} on success or {service, ok, path, error} on failure.
export def collect-service-logs [
    artifacts_base: string,
    stack_id: string,
    compose_files: list<string>,
    services: list<string>,
] {
    let logs_dir = ($artifacts_base | path join "docker" "logs")
    let f_args = ($compose_files | each {|f| ["-f" $f]} | flatten)

    # Guard: check whether any containers exist for this compose project,
    # regardless of running state (allows logs from stopped/exited containers).
    let avail_check = (^docker ps -a --filter $"label=com.docker.compose.project=($stack_id)" --format '{{.Label "com.docker.compose.service"}}' | complete)
    if $avail_check.exit_code != 0 {
        let stderr_msg = ($avail_check.stderr | str trim)
        let failed = ($services | each {|svc|
            {service: $svc, ok: false, path: "", error: $"stack availability check failed exit_code=($avail_check.exit_code): ($stderr_msg)"}
        })
        return {ok: false, services: $failed}
    }
    let known = ($avail_check.stdout | lines | where {|l| not ($l | is-empty)})
    if ($known | is-empty) {
        let failed = ($services | each {|svc|
            {service: $svc, ok: false, path: "", error: $"stack not available: no containers for project ($stack_id)"}
        })
        return {ok: false, services: $failed}
    }

    try {
        mkdir $logs_dir
    } catch {|e|
        let err = $"cannot create logs dir: ($e.msg)"
        let failed = ($services | each {|svc|
            {service: $svc, ok: false, path: "", error: $err}
        })
        return {ok: false, services: $failed}
    }

    let results = ($services | each {|svc|
        # Whitelist: alphanumeric, hyphens, underscores only. Rejects '/', '\', '..' etc.
        if not ($svc =~ '^[a-zA-Z0-9_-]+$') {
            {service: $svc, ok: false, path: "", error: $"invalid service name: ($svc)"}
        } else {
            let log_path = ($logs_dir | path join $"($svc).log")
            let err_path = ($logs_dir | path join $"($svc).err")

            # Stream stdout/stderr directly to files - no Nu-memory buffering.
            let launch_err = (try {
                ^docker compose ...$f_args -p $stack_id logs --no-color --timestamps $svc out> $log_path err> $err_path
                ""
            } catch {|e|
                $e.msg
            })
            let exit_code = $env.LAST_EXIT_CODE

            if ($launch_err | is-empty) and ($exit_code == 0) {
                if ($err_path | path exists) { try { rm $err_path } catch { } }
                {service: $svc, ok: true, path: $log_path}
            } else {
                let err = if not ($launch_err | is-empty) {
                    $launch_err
                } else if (($err_path | path exists) and (not ((open --raw $err_path | str trim) | is-empty))) {
                    open --raw $err_path | str trim
                } else {
                    $"docker compose logs exited ($exit_code)"
                }
                {service: $svc, ok: false, path: $log_path, error: $err}
            }
        }
    })

    let all_ok = ($results | all {|r| $r.ok})
    {ok: $all_ok, services: $results}
}
