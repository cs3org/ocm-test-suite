# CI blocker: evaluate which planned cells are blocked because a prerequisite
# failed, and emit blocked run/result artifacts.
#
# "blocked" is a first-class terminal status, distinct from "failed" and
# "not-implemented". A blocked cell carries a failure_reason that names the
# specific prerequisite cell_id that triggered the block.

use ../time/utc.nu [utc-now]
use ../run/execution-id.nu [execution-artifacts-path]
use ../publish/envelope.nu [publish-envelope-safe detect-execution-context collect-evidence]
use ../run/result-envelope.nu [build-result-v1]

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

# Write run.json for a terminal (blocked or capability-skipped) cell.
def write-terminal-run [
    meta_dir: string,
    execution_id: string,
    cell_id: string,
    artifact_name: string,
    status: string,
    exit_code: int,
    failure_reason: string,
    ts: string,
    matrix_key: string = "",
] {
    mut run = {
        schema_version: 1,
        id: $execution_id,
        execution_id: $execution_id,
        cell_id: $cell_id,
        artifact_name: $artifact_name,
        started_at: $ts,
        finished_at: $ts,
        status: $status,
        exit_code: $exit_code,
        stack_id: "",
        error: $failure_reason,
    }
    if not ($matrix_key | is-empty) { $run = ($run | upsert matrix_key $matrix_key) }
    $run | to json | save --force ($meta_dir | path join "run.json")
}

# Write result.v1.json for a terminal cell.
# extra_fields is merged into the result record (e.g. {capability_skip: ...}).
def write-terminal-result [
    artifacts_base: string,
    meta_dir: string,
    execution_id: string,
    cell_id: string,
    artifact_name: string,
    status: string,
    exit_code: int,
    failure_reason: string,
    ts: string,
    extra_fields: record,
    matrix_key: string = "",
] {
    let ctx = (detect-execution-context)
    let ev = (collect-evidence $artifacts_base)
    let base_fields = {
        id: $"result-($execution_id)",
        run_id: $execution_id,
        execution_id: $execution_id,
        cell_id: $cell_id,
        artifact_name: $artifact_name,
        started_at: $ts,
        finished_at: $ts,
        status: $status,
        exit_code: $exit_code,
        execution_context: $ctx,
        evidence: {
            total_count: $ev.counts.total,
            mitm_present: $ev.mitm_present,
            docker_logs_count: $ev.counts.docker_logs,
            cypress_screenshots_count: $ev.counts.cypress_screenshots,
            cypress_videos_count: $ev.counts.cypress_videos,
            cypress_downloads_count: $ev.counts.cypress_downloads,
            mitm_files_count: $ev.counts.mitm_files,
        },
        warnings: [],
        failure_reason: $failure_reason,
        matrix_key: $matrix_key,
    }
    (build-result-v1 ($base_fields | merge $extra_fields)) | to json --indent 2 | save --force ($meta_dir | path join "result.v1.json")
}

# Write both run.json and result.v1.json for a terminal cell into artifacts_base/meta/.
# extra_result_fields is merged into result.v1.json (e.g. {capability_skip: ...}).
def write-terminal-artifacts [
    artifacts_base: string,
    execution_id: string,
    cell_id: string,
    artifact_name: string,
    status: string,
    exit_code: int,
    failure_reason: string,
    extra_result_fields: record,
    ts: string,
    matrix_key: string = "",
] {
    let meta_dir = ($artifacts_base | path join "meta")
    mkdir $meta_dir
    write-terminal-run $meta_dir $execution_id $cell_id $artifact_name $status $exit_code $failure_reason $ts $matrix_key
    write-terminal-result $artifacts_base $meta_dir $execution_id $cell_id $artifact_name $status $exit_code $failure_reason $ts $extra_result_fields $matrix_key
}

# Write blocked run.json and result.v1.json into the cell's artifact directory.
# The artifact directory must already exist with meta/cell.json present.
# blocked_at is the timestamp to use; defaults to utc-now.
export def write-blocked-artifacts [
    artifacts_base: string,
    execution_id: string,
    cell_id: string,
    artifact_name: string,
    failure_reason: string,
    --blocked-at: string = "",
    --matrix-key: string = "",
] {
    let ts = if ($blocked_at | is-empty) { utc-now } else { $blocked_at }
    write-terminal-artifacts $artifacts_base $execution_id $cell_id $artifact_name "blocked" 0 $failure_reason {} $ts $matrix_key
}

# Write capability-skipped run.json and result.v1.json into the cell's artifact directory.
# The artifact directory must already exist with meta/cell.json present.
# skipped_at is the timestamp to use; defaults to utc-now.
export def write-capability-skipped-artifacts [
    artifacts_base: string,
    execution_id: string,
    cell_id: string,
    artifact_name: string,
    capability_skip: record,
    --skipped-at: string = "",
    --matrix-key: string = "",
] {
    let ts = if ($skipped_at | is-empty) { utc-now } else { $skipped_at }
    let failure_reason = ($capability_skip.rationale? | default "")
    write-terminal-artifacts $artifacts_base $execution_id $cell_id $artifact_name "capability-skipped" 0 $failure_reason {capability_skip: $capability_skip} $ts $matrix_key
}

# Shared inner: prepare the artifact dir and cell.json for a terminal planned
# cell, then invoke write_fn, publish the envelope, and return artifacts_base.
# write_fn receives (artifacts_base, execution_id) as positional arguments.
def emit-terminal-cell-artifact-inner [
    root: string,
    planned_cell: record,
    suite_id: string,
    suite_kind: string,
    write_fn: closure,
] {
    let exec_id = $planned_cell.execution_id
    let artifacts_base = (execution-artifacts-path
        $root $planned_cell.flow_id $planned_cell.pair $exec_id)
    mkdir ($artifacts_base | path join "meta")

    let suite_extra = if not ($suite_id | is-empty) {
        {suite_id: $suite_id, suite_kind: $suite_kind}
    } else {
        {}
    }
    let cell_meta = {
        schema_version: 1,
        cell_id: $planned_cell.cell_id,
        artifact_name: $planned_cell.artifact_name,
        flow_id: $planned_cell.flow_id,
        matrix_key: $planned_cell.matrix_key,
        scenario_module: ($planned_cell.scenario_module? | default $planned_cell.flow_id),
        pair: $planned_cell.pair,
        sender_platform: $planned_cell.sender_platform,
        sender_version: $planned_cell.sender_version,
        receiver_platform: ($planned_cell.receiver_platform? | default ""),
        receiver_version: ($planned_cell.receiver_version? | default ""),
        browser: ($planned_cell.browser? | default "chrome"),
        is_two_party: $planned_cell.is_two_party,
    } | merge $suite_extra
    $cell_meta | to json | save --force ($artifacts_base | path join "meta/cell.json")

    let mk = ($planned_cell.matrix_key? | default "" | into string | str trim)
    do $write_fn $artifacts_base $exec_id $mk
    publish-envelope-safe $artifacts_base
    $artifacts_base
}

# Emit a complete blocked artifact set for a planned cell.
# Initializes the artifact directory, writes cell.json, run.json, result.v1.json,
# and the publish envelope.
export def emit-blocked-cell-artifact [
    root: string,
    planned_cell: record,
    failure_reason: string,
    --suite-id: string = "",
    --suite-kind: string = "suite",
] {
    let fr = $failure_reason
    emit-terminal-cell-artifact-inner $root $planned_cell $suite_id $suite_kind {|ab, eid, mk|
        write-blocked-artifacts $ab $eid $planned_cell.cell_id $planned_cell.artifact_name $fr --matrix-key $mk
    }
}

# Emit a complete capability-skipped artifact set for a planned cell.
# Initializes the artifact directory, writes cell.json, run.json, result.v1.json,
# and the publish envelope.
# Returns artifacts_base.
export def emit-capability-skipped-cell-artifact [
    root: string,
    planned_cell: record,
    --suite-id: string = "",
    --suite-kind: string = "suite",
]: any -> string {
    let cap_skip = ($planned_cell.capability_skip? | default {rationale: ""})
    emit-terminal-cell-artifact-inner $root $planned_cell $suite_id $suite_kind {|ab, eid, mk|
        write-capability-skipped-artifacts $ab $eid $planned_cell.cell_id $planned_cell.artifact_name $cap_skip --matrix-key $mk
    }
}
