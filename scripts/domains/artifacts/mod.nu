# Artifacts domain: artifact inspection and log collection.

use ../../lib/cell.nu [compute-cell validate-cell-rules]
use ../../lib/artifacts-init.nu [read-last-execution-id]
use ../../lib/execution-id.nu [validate-execution-id validate-artifact-name execution-artifacts-path]
use ../../lib/domain/core/ocmts-root.nu [get-ocmts-root]
use ../../lib/compose-validate.nu [validate-compose-strict]
use ../../lib/docker-logs.nu [collect-service-logs]
use ../../lib/services/compose-files.nu [read-active-compose-files]
use ../../lib/publish-envelope.nu [emit-publish-envelope]

def main [] {
    print "Usage: nu scripts/ocmts.nu artifacts <verb> [flags]"
    print ""
    print "Verbs:"
    print "  list     List artifact runs for a cell"
    print "  show     Show metadata for a run"
    print "  collect  Collect artifacts for a run (use --include-logs for docker logs)"
    print "  publish  Regenerate suite-manifest.v1.json, summary.json, summary.md"
}

def "main list" [
    --scenario: string,
    --sender-platform: string,
    --sender-version: string,
    --receiver-platform: string = "",
    --receiver-version: string = "",
] {
    let root = get-ocmts-root
    let flow_id = (validate-cell-rules
        $scenario $sender_platform $sender_version "chrome"
        $receiver_platform $receiver_version)
    let cell = (compute-cell
        $scenario $sender_platform $sender_version "chrome"
        $receiver_platform $receiver_version $flow_id)
    let safe_name = (validate-artifact-name $cell.artifact_name)
    let base = ($root | path join "artifacts" $safe_name)
    if not ($base | path exists) {
        print $"No artifacts found for ($cell.artifact_name)"
        return
    }
    ls $base | where type == dir | sort-by modified --reverse | each {|row|
        let exec_id = ($row.name | path basename)
        let valid_id = (try { validate-execution-id $exec_id; true } catch { false })
        if not $valid_id {
            {execution_id: $exec_id, modified: $row.modified, status: "invalid-id", exit_code: ""}
        } else {
            let result_file = ($row.name | path join "meta/result.json")
            if ($result_file | path exists) {
                let r = (open $result_file)
                {
                    execution_id: $exec_id,
                    modified: $row.modified,
                    status: ($r.status? | default ""),
                    exit_code: ($r.exit_code? | default ""),
                }
            } else {
                {execution_id: $exec_id, modified: $row.modified, status: "", exit_code: ""}
            }
        }
    }
}

def "main show" [
    --scenario: string,
    --sender-platform: string,
    --sender-version: string,
    --receiver-platform: string = "",
    --receiver-version: string = "",
    --execution-id: string = "",
] {
    let root = get-ocmts-root
    let flow_id = (validate-cell-rules
        $scenario $sender_platform $sender_version "chrome"
        $receiver_platform $receiver_version)
    let cell = (compute-cell
        $scenario $sender_platform $sender_version "chrome"
        $receiver_platform $receiver_version $flow_id)
    let exec_id = if ($execution_id | is-empty) {
        read-last-execution-id $cell.artifact_name
    } else {
        $execution_id
    }
    let base = (execution-artifacts-path $root $cell.artifact_name $exec_id)
    let result_file = ($base | path join "meta/result.json")
    let run_file = ($base | path join "meta/run.json")
    mut summary = {artifacts_base: $base}
    if ($run_file | path exists) { $summary = ($summary | upsert run (open $run_file)) }
    if ($result_file | path exists) { $summary = ($summary | upsert result (open $result_file)) }
    if ($summary | reject artifacts_base | is-empty) {
        error make {msg: $"No metadata found for execution_id=($exec_id)"}
    }
    $summary
}

def "main collect" [
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
        read-last-execution-id $cell.artifact_name
    } else {
        $execution_id
    }
    let base = (execution-artifacts-path $root $cell.artifact_name $exec_id)

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
        ["platform" "platform-db" "platform-cache"]
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
        if $s.ok {
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

# Regenerate suite-manifest.v1.json, summary.json, summary.md for a run.
# Pass --artifacts-base with the full path to the execution artifact root,
# e.g. artifacts/<artifact_name>/<execution_id>.
def "main publish" [
    --artifacts-base: string,
    --scenario: string = "",
    --sender-platform: string = "",
    --sender-version: string = "",
    --receiver-platform: string = "",
    --receiver-version: string = "",
    --execution-id: string = "",
] {
    # If --artifacts-base is given, use it directly.
    let base = if not ($artifacts_base | is-empty) {
        $artifacts_base
    } else {
        let root = get-ocmts-root
        let flow_id = (validate-cell-rules
            $scenario $sender_platform $sender_version "chrome"
            $receiver_platform $receiver_version)
        let cell = (compute-cell
            $scenario $sender_platform $sender_version "chrome"
            $receiver_platform $receiver_version $flow_id)
        let exec_id = if ($execution_id | is-empty) {
            read-last-execution-id $cell.artifact_name
        } else {
            $execution_id
        }
        execution-artifacts-path $root $cell.artifact_name $exec_id
    }
    if not ($base | path exists) {
        error make {msg: $"Artifacts base not found: ($base)"}
    }
    emit-publish-envelope $base
    print $"Published envelope for ($base)"
    print $"  meta/suite-manifest.v1.json"
    print $"  meta/summary.json"
    print $"  meta/summary.md"
}
