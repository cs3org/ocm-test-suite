# Regenerate suite-manifest.v1.json, summary.json, summary.md for a run.
# Pass --artifacts-base with the full path to the execution artifact root,
# e.g. artifacts/<flow_id>/<pair>/<execution_id>.

use ../../lib/matrix/cell.nu [compute-cell validate-cell-rules]
use ../../lib/artifacts/init.nu [read-last-execution-id]
use ../../lib/run/execution-id.nu [execution-artifacts-path]
use ../../lib/domain/core/ocmts-root.nu [get-ocmts-root]
use ../../lib/publish/envelope.nu [emit-publish-envelope]

def main [
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
            read-last-execution-id $cell.flow_id $cell.pair
        } else {
            $execution_id
        }
        execution-artifacts-path $root $cell.flow_id $cell.pair $exec_id
    }
    if not ($base | path exists) {
        error make {msg: $"Artifacts base not found: ($base)"}
    }
    emit-publish-envelope $base
    print $"Published envelope for ($base)"
    print $"  meta/suite-manifest.v1.json"
}
