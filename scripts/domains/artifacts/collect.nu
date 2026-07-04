# Collect artifacts for a run (use --include-logs for docker logs).

use ../../lib/matrix/cell.nu [compute-cell validate-cell-rules]
use ../../lib/artifacts/init.nu [read-last-execution-id]
use ../../lib/run/execution-id.nu [execution-artifacts-path]
use ../../lib/domain/core/ocmts-root.nu [get-ocmts-root]
use ../../lib/run/metadata.nu [read-run-meta]
use ../../lib/compose/validate.nu [validate-compose-strict]
use ../../lib/compose/logs.nu [collect-service-logs]
use ../../lib/services/compose-files.nu [
    read-compose-files-from-manifest
]

# Resolve sorted compose project service names for the active file set.
# Returns null when docker compose config --services fails.
def compose-project-services [
    artifacts_base: string,
    stack_id: string,
    compose_files: list<string>,
] {
    let f_args = ($compose_files | each {|f| ["-f" $f]} | flatten)
    let env_file = ($artifacts_base | path join "compose" "inputs" "stack.env")
    let env_file_args = if ($env_file | path exists) { ["--env-file" $env_file] } else { [] }
    let cfg = (^docker compose ...$env_file_args ...$f_args -p $stack_id config --services | complete)
    if $cfg.exit_code != 0 {
        return null
    }
    ($cfg.stdout | lines | where {|l| not ($l | is-empty)} | sort)
}

# True when logs_dir already has a non-empty .log file for every expected service.
def cached-logs-cover-services [logs_dir: string, services: list<string>] {
    if ($services | is-empty) {
        return false
    }
    $services | all {|svc|
        let log_path = ($logs_dir | path join $"($svc).log")
        if not ($log_path | path exists) {
            false
        } else {
            (ls $log_path | get 0 | get size) != 0b
        }
    }
}

# Exported for regression tests: paths for expected services with absent or
# zero-byte log files under logs_dir.
export def missing-or-empty-expected-service-logs [
    logs_dir: string,
    expected_services: list<string>,
] {
    $expected_services | each {|svc|
        let log_path = ($logs_dir | path join $"($svc).log")
        if not ($log_path | path exists) {
            $log_path
        } else if (ls $log_path | get 0 | get size) == 0b {
            $log_path
        } else {
            null
        }
    } | where {|p| $p != null}
}

# Exported for regression tests: partial cache must not satisfy this check.
export def logs-cache-covers-compose-project [
    artifacts_base: string,
    stack_id: string,
    compose_files: list<string>,
] {
    let logs_dir = ($artifacts_base | path join "docker" "logs")
    if not ($logs_dir | path exists) {
        return false
    }
    let expected = (compose-project-services $artifacts_base $stack_id $compose_files)
    if $expected == null {
        return false
    }
    cached-logs-cover-services $logs_dir $expected
}

def main [
    --flow: string,
    --sender-platform: string,
    --sender-version: string,
    --receiver-platform: string = "",
    --receiver-version: string = "",
    --execution-id: string = "",
    --include-logs,
] {
    let root = get-ocmts-root
    validate-cell-rules $flow $sender_platform $sender_version "chrome" $receiver_platform $receiver_version
    let cell = (compute-cell $flow $sender_platform $sender_version "chrome" $receiver_platform $receiver_version)
    let exec_id = if ($execution_id | is-empty) {
        read-last-execution-id $cell.flow_id $cell.pair
    } else {
        $execution_id
    }
    let base = (execution-artifacts-path $root $cell.flow_id $cell.pair $exec_id)

    let run_meta = (read-run-meta $base)
    let stack_id = $run_meta.stack_id

    if not $include_logs {
        print "Hint: pass --include-logs to collect docker service logs."
        print $"Artifacts: ($base)"
        return
    }

    # All-services discovery: empty list resolves targets via compose config --services.
    let log_services = []

    let logs_dir = ($base | path join "docker" "logs")
    let compose_files = (read-compose-files-from-manifest $base $root)

    if (logs-cache-covers-compose-project $base $stack_id $compose_files) {
        ls $logs_dir | where name =~ '\.log$' | each {|f| print $"Collected: ($f.name)"}
        return
    }

    # Some or all logs are missing; attempt live collection.

    # Optional: validate compose file set before collecting logs.
    let logs_resolved_path = ($base | path join "compose" "compose.resolved.logs.yml")
    try {
        validate-compose-strict $compose_files $stack_id $logs_resolved_path
    } catch {|e|
        print $"WARNING: compose validation before log collection failed: ($e.msg)"
    }

    let result = (collect-service-logs $base $stack_id $compose_files $log_services)
    $result.services | each {|s|
        if ($s.skipped? | default false) {
            let note = ($s.note? | default "SKIPPED")
            print $"Skipped: ($s.service) - ($note)"
        } else if $s.ok {
            print $"Collected: ($s.path)"
        } else {
            let err = ($s.error? | default "unknown")
            print $"FAILED: ($s.service) - ($err)"
        }
    }
    if not $result.ok {
        # If the stack is gone (teardown already ran), surface which logs are
        # missing and explain that live collection is no longer possible.
        let stack_gone = ($result.services | any {|s|
            ((not $s.ok)
                and (($s.error? | default "") | str contains "no containers"))
        })
        if $stack_gone {
            let expected = (compose-project-services $base $stack_id $compose_files)
            if $expected != null {
                let missing_paths = (missing-or-empty-expected-service-logs $logs_dir $expected)
                let missing_list = ($missing_paths | each {|p| $"  ($p)"} | str join "\n")
                error make {msg: $"Log collection failed: stack is already torn down. Missing or empty logs:\n($missing_list)"}
            } else {
                let empty_logs = if ($logs_dir | path exists) {
                    ls $logs_dir
                        | where name =~ '\.log$'
                        | where {|f| $f.size == 0b}
                        | get name
                } else {
                    []
                }
                let detail = if ($empty_logs | is-empty) {
                    "compose project service list is unavailable; no zero-byte cached logs to report."
                } else {
                    let empty_list = ($empty_logs | each {|p| $"  ($p)"} | str join "\n")
                    $"compose project service list is unavailable. Zero-byte cached logs:\n($empty_list)"
                }
                error make {msg: $"Log collection failed: stack is already torn down. ($detail)"}
            }
        } else {
            error make {msg: "Log collection failed for one or more services. See output above."}
        }
    }
}
