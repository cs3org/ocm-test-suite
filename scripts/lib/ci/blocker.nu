# CI blocker: evaluate which planned cells are blocked because a prerequisite
# failed, and emit blocked run/result artifacts.
#
# "blocked" is a first-class terminal status, distinct from "failed" and
# "not-implemented". A blocked cell carries a failure_reason that names the
# specific prerequisite cell_id that triggered the block.

use ../run-metadata.nu [utc-now write-compact-result]
use ../execution-id.nu [execution-artifacts-path]
use ../publish-envelope.nu [publish-envelope-safe]

# Evaluate the block state for every planned cell given a set of
# already-failed cell_ids. Returns a list of records:
#   [{cell_id, blocked, status, failure_reason}]
# "blocked" is true only when depends_on contains a failed cell_id.
# Status is "blocked" for blocked cells, "pending" for others.
export def eval-blocked-cells [
    planned_cells: list,
    failed_cell_ids: list<string>,
] {
    $planned_cells | each {|c|
        let deps = ($c.depends_on? | default [])
        let matched_deps = ($deps | where {|d| $d in $failed_cell_ids})
        let blocking_dep = if ($matched_deps | is-empty) { null } else { $matched_deps | first }
        if $blocking_dep != null {
            {
                cell_id: $c.cell_id,
                blocked: true,
                status: "blocked",
                failure_reason: $"prerequisite ($blocking_dep) failed",
            }
        } else {
            {
                cell_id: $c.cell_id,
                blocked: false,
                status: "pending",
                failure_reason: "",
            }
        }
    }
}

# Write blocked run.json and result.json into the cell's artifact directory.
# The artifact directory must already exist with meta/cell.json present.
# blocked_at is the timestamp to use; defaults to utc-now.
export def write-blocked-artifacts [
    artifacts_base: string,
    execution_id: string,
    cell_id: string,
    artifact_name: string,
    failure_reason: string,
    --blocked-at: string = "",
] {
    let ts = if ($blocked_at | is-empty) { utc-now } else { $blocked_at }
    let meta_dir = ($artifacts_base | path join "meta")
    mkdir $meta_dir

    let run = {
        schema_version: 1,
        id: $execution_id,
        execution_id: $execution_id,
        cell_id: $cell_id,
        artifact_name: $artifact_name,
        started_at: $ts,
        finished_at: $ts,
        status: "blocked",
        exit_code: 0,
        stack_id: "",
        error: $failure_reason,
    }
    $run | to json | save --force ($meta_dir | path join "run.json")

    let result = {
        schema_version: 1,
        id: $"result-($execution_id)",
        run_id: $execution_id,
        execution_id: $execution_id,
        cell_id: $cell_id,
        exit_code: 0,
        status: "blocked",
        finished_at: $ts,
        failure_reason: $failure_reason,
    }
    $result | to json | save --force ($meta_dir | path join "result.json")
}

# Emit a complete blocked artifact set for a planned cell.
# Initializes the artifact directory, writes cell.json, run.json, result.json,
# and the publish envelope.
export def emit-blocked-cell-artifact [
    root: string,
    planned_cell: record,
    failure_reason: string,
    --suite-id: string = "",
    --suite-kind: string = "suite",
] {
    use ../execution-id.nu [execution-artifacts-path]

    let exec_id = $planned_cell.execution_id
    let artifacts_base = (execution-artifacts-path
        $root $planned_cell.flow_id $planned_cell.pair $exec_id)
    mkdir ($artifacts_base | path join "meta")

    # Write cell.json so the publish envelope can read it.
    mut cell_meta = {
        schema_version: 1,
        cell_id: $planned_cell.cell_id,
        artifact_name: $planned_cell.artifact_name,
        flow_id: $planned_cell.flow_id,
        scenario: $planned_cell.scenario,
        scenario_module: ($planned_cell.scenario_module? | default $planned_cell.flow_id),
        pair: $planned_cell.pair,
        sender_platform: $planned_cell.sender_platform,
        sender_version: $planned_cell.sender_version,
        receiver_platform: ($planned_cell.receiver_platform? | default ""),
        receiver_version: ($planned_cell.receiver_version? | default ""),
        browser: ($planned_cell.browser? | default "chrome"),
        is_two_party: $planned_cell.is_two_party,
    }
    if not ($suite_id | is-empty) {
        $cell_meta = ($cell_meta | upsert suite_id $suite_id)
        $cell_meta = ($cell_meta | upsert suite_kind $suite_kind)
    }
    $cell_meta | to json | save --force ($artifacts_base | path join "meta/cell.json")

    (write-blocked-artifacts
        $artifacts_base $exec_id
        $planned_cell.cell_id $planned_cell.artifact_name
        $failure_reason)

    publish-envelope-safe $artifacts_base
    $artifacts_base
}
