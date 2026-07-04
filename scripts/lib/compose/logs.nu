# Collect docker compose service logs and write them to artifacts docker/logs/.

# Collect logs for the given services using the active compose file set.
# An empty services list means all services in the compose project definition
# (resolved via docker compose config --services for the active file set).
# Writes one file per service under artifacts_base/docker/logs/<service>.log.
# Returns {ok: bool, services: list<record>} where each service record is
# {service, ok, path} on success, {service, ok, path, skipped, note} when
# skipped (no container exists yet for the compose service name), or
# {service, ok, path, error} on failure.
export def collect-service-logs [
    artifacts_base: string,
    stack_id: string,
    compose_files: list<string>,
    services: list<string>,
] {
    let logs_dir = ($artifacts_base | path join "docker" "logs")
    let f_args = ($compose_files | each {|f| ["-f" $f]} | flatten)
    let env_file = ($artifacts_base | path join "compose" "inputs" "stack.env")
    let env_file_args = if ($env_file | path exists) { ["--env-file" $env_file] } else { [] }

    # Guard: check whether any containers exist for this compose project,
    # regardless of running state (allows logs from stopped/exited containers).
    let avail_check = (^docker ps -a --filter $"label=com.docker.compose.project=($stack_id)" --format '{{.Label "com.docker.compose.service"}}' | complete)
    if $avail_check.exit_code != 0 {
        let stderr_msg = ($avail_check.stderr | str trim)
        let failed = if ($services | is-empty) {
            [{service: "", ok: false, path: "", error: $"stack availability check failed exit_code=($avail_check.exit_code): ($stderr_msg)"}]
        } else {
            ($services | each {|svc|
                {service: $svc, ok: false, path: "", error: $"stack availability check failed exit_code=($avail_check.exit_code): ($stderr_msg)"}
            })
        }
        return {ok: false, services: $failed}
    }
    let known = ($avail_check.stdout | lines | where {|l| not ($l | is-empty)} | sort)

    let target_services = if ($services | is-empty) {
        let cfg = (^docker compose ...$env_file_args ...$f_args -p $stack_id config --services | complete)
        if $cfg.exit_code != 0 {
            let stderr_msg = ($cfg.stderr | str trim)
            return {
                ok: false
                services: [{
                    service: ""
                    ok: false
                    path: ""
                    error: $"compose project service list failed exit_code=($cfg.exit_code): ($stderr_msg)"
                }]
            }
        }
        ($cfg.stdout | lines | where {|l| not ($l | is-empty)} | sort)
    } else {
        $services
    }

    try {
        mkdir $logs_dir
    } catch {|e|
        let err = $"cannot create logs dir: ($e.msg)"
        let failed = if ($target_services | is-empty) {
            [{service: "", ok: false, path: "", error: $err}]
        } else {
            ($target_services | each {|svc|
                {service: $svc, ok: false, path: "", error: $err}
            })
        }
        return {ok: false, services: $failed}
    }

    let results = ($target_services | each {|svc|
        # Whitelist: alphanumeric, hyphens, underscores only. Rejects '/', '\', '..' etc.
        if not ($svc =~ '^[a-zA-Z0-9_-]+$') {
            {service: $svc, ok: false, path: "", error: $"invalid service name: ($svc)"}
        } else if not ($known | any {|k| $k == $svc}) {
            # Target is in the compose project (or caller list) but docker ps
            # found no container with this compose service label yet.
            let log_path = ($logs_dir | path join $"($svc).log")
            let err_path = ($logs_dir | path join $"($svc).err")
            let note = $"SKIPPED: no container found for compose service: ($svc)"
            try {
                $note | save --force $log_path
                if ($err_path | path exists) { try { rm $err_path } catch { } }
                {service: $svc, ok: true, path: $log_path, skipped: true, note: $note}
            } catch {|e|
                {service: $svc, ok: false, path: $log_path, error: $"cannot write skipped log placeholder: ($e.msg)"}
            }
        } else {
            let log_path = ($logs_dir | path join $"($svc).log")
            let err_path = ($logs_dir | path join $"($svc).err")

            # Use | complete so exit_code is reliable - out>/err> redirections
            # reset LAST_EXIT_CODE to 0, making it untrustworthy.
            let result = (try {
                ^docker compose ...$f_args ...$env_file_args -p $stack_id logs --no-color --timestamps $svc | complete
            } catch {|e|
                {exit_code: 1, stdout: "", stderr: $e.msg}
            })

            if $result.exit_code == 0 {
                $result.stdout | save --force $log_path
                if ($err_path | path exists) { try { rm $err_path } catch { } }
                {service: $svc, ok: true, path: $log_path}
            } else {
                let stderr_text = ($result.stderr | str trim)
                let err = if not ($stderr_text | is-empty) {
                    $stderr_text
                } else {
                    $"docker compose logs exited ($result.exit_code)"
                }
                if not ($result.stdout | is-empty) {
                    $result.stdout | save --force $log_path
                }
                if not ($stderr_text | is-empty) {
                    $stderr_text | save --force $err_path
                }
                {service: $svc, ok: false, path: $log_path, error: $err}
            }
        }
    })

    let all_ok = ($results | all {|r| $r.ok})
    {ok: $all_ok, services: $results}
}
