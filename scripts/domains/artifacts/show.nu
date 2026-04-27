# Show metadata for an artifact run.

use ../../lib/matrix/cell.nu [compute-cell validate-cell-rules]
use ../../lib/artifacts/init.nu [read-last-execution-id]
use ../../lib/run/execution-id.nu [execution-artifacts-path]
use ../../lib/domain/core/ocmts-root.nu [get-ocmts-root]

def main [
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
        read-last-execution-id $cell.flow_id $cell.pair
    } else {
        $execution_id
    }
    let base = (execution-artifacts-path $root $cell.flow_id $cell.pair $exec_id)
    let result_file = ($base | path join "meta/result.v1.json")
    let run_file = ($base | path join "meta/run.json")
    mut summary = {artifacts_base: $base}
    if ($run_file | path exists) { $summary = ($summary | upsert run (open $run_file)) }
    if ($result_file | path exists) { $summary = ($summary | upsert result (open $result_file)) }
    if ($summary | reject artifacts_base | is-empty) {
        error make {msg: $"No metadata found for execution_id=($exec_id)"}
    }
    $summary
}
