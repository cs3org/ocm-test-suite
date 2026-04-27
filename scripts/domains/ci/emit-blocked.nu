# Emit a blocked artifact for a single planned cell.
# Called in CI when a prerequisite cell fails and we need to record blocked
# status for dependent cells without running them.
#
# flow_id, pair, artifact_name, and cell_id are derived from scenario +
# participant inputs when not provided explicitly. This allows the workflow
# to call emit-blocked with only the inputs it already has.

use ../../lib/ci/blocker.nu [emit-blocked-cell-artifact]
use ../../lib/matrix/cell.nu [compute-cell]
use ../../lib/domain/core/ocmts-root.nu [get-ocmts-root]
use ../../lib/matrix/rules-gen.nu [load-matrix-rules]

def main [
    --cell-id: string = "",         # cell_id; derived from scenario+participants if omitted
    --execution-id: string,         # execution_id for this blocked run
    --flow-id: string = "",         # flow_id; derived from scenario via matrix-rules if omitted
    --scenario: string,             # scenario key (required; used to derive missing fields)
    --pair: string = "",            # pair slug; derived from sender+receiver if omitted
    --artifact-name: string = "",   # artifact_name; derived from sender+receiver if omitted
    --sender-platform: string,
    --sender-version: string,
    --receiver-platform: string = "",
    --receiver-version: string = "",
    --failure-reason: string,       # concrete reason naming the failed prerequisite
    --suite-id: string = "",
    --suite-kind: string = "suite",
] {
    let root = get-ocmts-root

    # Look up flow_id from the matrix rules SSOT when not explicitly provided.
    let eff_flow_id = if not ($flow_id | is-empty) {
        $flow_id
    } else {
        let rules = (load-matrix-rules $root)
        let sc_rules = ($rules.scenarios? | default {} | get? $scenario | default {})
        $sc_rules.flow_id? | default $scenario
    }

    # Derive pair, artifact_name, cell_id from scenario+participants when omitted.
    let derived = (compute-cell $scenario $sender_platform $sender_version "chrome"
        $receiver_platform $receiver_version $eff_flow_id)
    let eff_cell_id = if ($cell_id | is-empty) { $derived.cell_id } else { $cell_id }
    let eff_pair = if ($pair | is-empty) { $derived.pair } else { $pair }
    let eff_artifact_name = if ($artifact_name | is-empty) { $derived.artifact_name } else { $artifact_name }

    let is_two_party = not ($receiver_platform | is-empty)
    let planned_cell = {
        cell_id: $eff_cell_id,
        execution_id: $execution_id,
        flow_id: $eff_flow_id,
        scenario: $scenario,
        scenario_module: $eff_flow_id,
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
