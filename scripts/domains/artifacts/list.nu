# List artifact runs for a cell.

use ../../lib/matrix/cell.nu [compute-cell validate-cell-rules]
use ../../lib/run/execution-id.nu [validate-execution-id]
use ../../lib/domain/core/ocmts-root.nu [get-ocmts-root]

def main [
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
    let base = ($root | path join "artifacts" $cell.flow_id $cell.pair)
    if not ($base | path exists) {
        print $"No artifacts found for ($cell.flow_id)/($cell.pair)"
        return
    }
    ls $base | where type == dir | sort-by modified --reverse | each {|row|
        let exec_id = ($row.name | path basename)
        let valid_id = (try { validate-execution-id $exec_id; true } catch { false })
        if not $valid_id {
            {execution_id: $exec_id, modified: $row.modified, status: "invalid-id", exit_code: ""}
        } else {
            let result_file = ($row.name | path join "meta/result.v1.json")
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
