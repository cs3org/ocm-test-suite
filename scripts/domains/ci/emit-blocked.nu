# Emit a blocked artifact for a single planned cell.
# flow_id, pair, artifact_name, and cell_id are derived from tuple inputs
# when not provided explicitly.

use ../../lib/ci/blocker.nu [emit-blocked-cell-artifact]
use ../../lib/matrix/cell.nu [
    assert-matrix-entry-enabled
    compute-cell
    validate-cell-rules
]
use ../../lib/domain/core/ocmts-root.nu [get-ocmts-root]

def main [
    --cell-id: string = "",
    --execution-id: string,
    --flow: string,
    --pair: string = "",
    --artifact-name: string = "",
    --sender-platform: string,
    --sender-version: string,
    --receiver-platform: string = "",
    --receiver-version: string = "",
    --failure-reason: string,
    --suite-id: string = "",
    --suite-kind: string = "suite",
] {
    let root = get-ocmts-root

    assert-matrix-entry-enabled $flow $sender_platform $receiver_platform
    (validate-cell-rules $flow $sender_platform $sender_version "chrome"
        $receiver_platform $receiver_version)

    let derived = (compute-cell $flow $sender_platform $sender_version "chrome"
        $receiver_platform $receiver_version)
    let eff_cell_id = if ($cell_id | is-empty) { $derived.cell_id } else { $cell_id }
    let eff_pair = if ($pair | is-empty) { $derived.pair } else { $pair }
    let eff_artifact_name = if ($artifact_name | is-empty) { $derived.artifact_name } else { $artifact_name }

    let is_two_party = not ($receiver_platform | is-empty)
    let planned_cell = {
        cell_id: $eff_cell_id,
        execution_id: $execution_id,
        flow_id: $flow,
        matrix_key: $derived.matrix_key,
        pair: $eff_pair,
        artifact_name: $eff_artifact_name,
        sender_platform: $sender_platform,
        sender_version: $sender_version,
        receiver_platform: $receiver_platform,
        receiver_version: $receiver_version,
        is_two_party: $is_two_party,
        browser: "chrome",
    }
    let base = (emit-blocked-cell-artifact $root $planned_cell $failure_reason
        --suite-id $suite_id --suite-kind $suite_kind)
    print $"Blocked artifact written to ($base)"
}
