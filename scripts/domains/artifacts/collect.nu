# Collect artifacts for a run (use --include-logs for docker logs).

use ../../lib/matrix/cell.nu [compute-cell validate-cell-rules]
use ../../lib/artifacts/init.nu [read-last-execution-id]
use ../../lib/run/execution-id.nu [execution-artifacts-path]
use ../../lib/domain/core/ocmts-root.nu [get-ocmts-root]
use ../../lib/compose/validate.nu [validate-compose-strict]
use ../../lib/compose/logs.nu [collect-service-logs]
use ../../lib/services/compose-files.nu [read-active-compose-files]

def main [
    --scenario: string,
    --sender-platform: string,
    --sender-version: string,
    --receiver-platform: string = "",
    --receiver-version: string = "",
    --execution-id: string = "",
    --include-logs,
] {
    let root = get-ocmts-root
    let flow_id = (validate-cell-rules
        $scenario $sender_platform $sender_version "chrome"
        $receiver_platform $receiver_version)
    let cell = (compute-cell
        $scenario $sender_platform $sender_version "chrome"
        $receiver_platform $receiver_version $flow_id)
    let exec_id = if ($execution_id | is-empty) {
        read-last-execution-id $cell.flow_id $cell.pair
    } else {
        $execution_id
    }
    let base = (execution-artifacts-path $root $cell.flow_id $cell.pair $exec_id)

    let stack_id_file = ($base | path join "compose" "stack_id.txt")
    if not ($stack_id_file | path exists) {
        error make {msg: $"No stack_id found for execution_id=($exec_id). Artifacts may be missing."}
    }
    let stack_id = (open --raw $stack_id_file | str trim)

    if not $include_logs {
        print "Hint: pass --include-logs to collect docker service logs."
        print $"Artifacts: ($base)"
        return
    }

    # Determine expected services for this topology.
    let log_services = if $cell.is_two_party {
        ["sender" "sender-db" "sender-cache" "receiver" "receiver-db" "receiver-cache" "mitm"]
    } else {
        ["sender" "sender-db" "sender-cache"]
    }

    # If all expected logs already exist (e.g., collected during `services up run`),
    # report them and skip live docker collection.
    let logs_dir = ($base | path join "docker" "logs")
    let expected_paths = ($log_services | each {|svc|
        {service: $svc, path: ($logs_dir | path join $"($svc).log")}
    })
    let all_cached = ($expected_paths | all {|e| $e.path | path exists})
    if $all_cached {
        $expected_paths | each {|e| print $"Collected: ($e.path)"}
        return
    }

    # Some or all logs are missing; attempt live collection.
    let base_yml = ($root | path join "config/compose/base.yml")
    let compose_files = (read-active-compose-files $base $base_yml)

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
            let missing = ($expected_paths | where {|e| not ($e.path | path exists)})
            let missing_list = ($missing | each {|e| $"  ($e.path)"} | str join "\n")
            error make {msg: $"Log collection failed: stack is already torn down. Missing logs:\n($missing_list)"}
        } else {
            error make {msg: "Log collection failed for one or more services. See output above."}
        }
    }
}
