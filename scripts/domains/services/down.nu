# Tear down services for a cell by execution_id or last known run.

use ../../lib/compose/validate.nu [validate-compose-strict]
use ../../lib/run/metadata.nu [
    update-run-lifecycle
    utc-now
]
use ../../lib/run/execution-id.nu [execution-artifacts-path]
use ../../lib/matrix/cell.nu [compute-cell validate-cell-rules]
use ../../lib/artifacts/init.nu [read-last-execution-id]
use ../../lib/domain/core/ocmts-root.nu [get-ocmts-root]
use ../../lib/services/compose-files.nu [
    build-f-args read-active-compose-files read-compose-env-file
]
use ../../lib/services/lifecycle.nu [
    cleanup-temp
    ensure-network-gone
]

def main [
    --scenario: string,
    --sender-platform: string,
    --sender-version: string,
    --receiver-platform: string = "",
    --receiver-version: string = "",
    --execution-id: string = "",
    --preserve-temp,
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
    let artifacts_base = (execution-artifacts-path $root $cell.flow_id $cell.pair $exec_id)

    let stack_id_file = ($artifacts_base | path join "compose" "stack_id.txt")
    if not ($stack_id_file | path exists) {
        error make {msg: $"No stack_id found for execution_id=($exec_id). Artifacts may be missing."}
    }
    let stack_id = (open --raw $stack_id_file | str trim)

    print $"Tearing down ($cell.cell_id) [stack_id=($stack_id)]..."
    let base_yml = ($root | path join "config/compose/base.yml")
    let active_files_path = ($artifacts_base | path join "compose" "active-files.txt")
    if not ($active_files_path | path exists) {
        print "WARNING: active-files.txt not found; using base-only file set (legacy artifacts)"
    }
    let down_files = (read-active-compose-files $artifacts_base $base_yml)
    let env_file = (read-compose-env-file $artifacts_base)
    let env_args = if ($env_file | is-empty) { [] } else { ["--env-file" $env_file] }
    let f_args_down = (build-f-args $down_files)
    try {
        (validate-compose-strict $down_files $stack_id
            ($artifacts_base | path join "compose" "compose.resolved.down.yml")
            $env_file)
    } catch {|ve|
        cleanup-temp $exec_id $preserve_temp
        let finished_at = (utc-now)
        (update-run-lifecycle $artifacts_base "down-failed" --phase "compose-down"
            --finished-at $finished_at --exit-code 1 --error $ve.msg)
        error make {msg: $"cleanup/down failed: down file set validation failed: ($ve.msg)"}
    }
    let down_err = (try {
        ^docker compose ...$env_args ...$f_args_down -p $stack_id down --volumes
        ensure-network-gone $stack_id
        null
    } catch {|e|
        $e.msg
    })

    cleanup-temp $exec_id $preserve_temp
    let finished_at = (utc-now)
    if $down_err != null {
        (update-run-lifecycle $artifacts_base "down-failed" --phase "compose-down"
            --finished-at $finished_at --exit-code 1 --error $down_err)
        error make {msg: $"cleanup/down failed: ($down_err)"}
    }
    (update-run-lifecycle $artifacts_base "stopped" --phase "compose-down"
        --finished-at $finished_at)
    print $"Services down. execution_id=($exec_id) status=stopped"
}
