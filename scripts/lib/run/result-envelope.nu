# Canonical builder for result.v1.json artifacts.
# Single source of truth for the result record schema.
# All three writers (blocker.nu, finalize.nu, metadata.nu) call build-result-v1.

# Valid status values for result.v1.json.
const VALID_RESULT_STATUSES = [
    "passed"
    "failed"
    "blocked"
    "missing"
    "running"
    "capability-skipped"
    "unknown"
    "infra-failed"
    "cleanup-failed"
]

# Build a result.v1.json record from the supplied fields.
# Required fields: id, run_id, execution_id, cell_id, status, exit_code.
# Optional fields (omitted from output when null/absent): artifact_name,
# started_at, finished_at, execution_context, evidence, warnings,
# failure_reason, verdict, capability_skip, suite_id, suite_kind.
#
# Enforces: schema_version always 1; status must be a known value;
# id/run_id/execution_id/cell_id must not be empty.
export def build-result-v1 [fields: record] {
    let id = ($fields.id? | default "")
    let run_id = ($fields.run_id? | default "")
    let execution_id = ($fields.execution_id? | default "")
    let cell_id = ($fields.cell_id? | default "")
    let status = ($fields.status? | default "")
    let exit_code = ($fields.exit_code? | default null)

    if ($id | is-empty) { error make {msg: "build-result-v1: id is required"} }
    if ($run_id | is-empty) { error make {msg: "build-result-v1: run_id is required"} }
    if ($execution_id | is-empty) { error make {msg: "build-result-v1: execution_id is required"} }
    if ($cell_id | is-empty) { error make {msg: "build-result-v1: cell_id is required"} }
    if ($status | is-empty) { error make {msg: "build-result-v1: status is required"} }
    if $exit_code == null { error make {msg: "build-result-v1: exit_code is required"} }
    if not ($status in $VALID_RESULT_STATUSES) {
        error make {msg: $"build-result-v1: unknown status '($status)'; expected one of: ($VALID_RESULT_STATUSES | str join ', ')"}
    }

    mut r = {
        schema_version: 1,
        id: $id,
        run_id: $run_id,
        execution_id: $execution_id,
        cell_id: $cell_id,
        status: $status,
        exit_code: $exit_code,
    }

    let artifact_name = ($fields.artifact_name? | default null)
    let started_at = ($fields.started_at? | default null)
    let finished_at = ($fields.finished_at? | default null)
    let execution_context = ($fields.execution_context? | default null)
    let evidence = ($fields.evidence? | default null)
    let warnings = ($fields.warnings? | default null)
    let failure_reason = ($fields.failure_reason? | default null)
    let verdict = ($fields.verdict? | default null)
    let capability_skip = ($fields.capability_skip? | default null)
    let suite_id = ($fields.suite_id? | default null)
    let suite_kind = ($fields.suite_kind? | default null)

    if $artifact_name != null { $r = ($r | upsert artifact_name $artifact_name) }
    if $started_at != null { $r = ($r | upsert started_at $started_at) }
    if $finished_at != null { $r = ($r | upsert finished_at $finished_at) }
    if $execution_context != null { $r = ($r | upsert execution_context $execution_context) }
    if $evidence != null { $r = ($r | upsert evidence $evidence) }
    if $warnings != null { $r = ($r | upsert warnings $warnings) }
    if $failure_reason != null and (not ($failure_reason | is-empty)) {
        $r = ($r | upsert failure_reason $failure_reason)
    }
    if $verdict != null { $r = ($r | upsert verdict $verdict) }
    if $capability_skip != null { $r = ($r | upsert capability_skip $capability_skip) }
    if $suite_id != null and (not ($suite_id | is-empty)) {
        $r = ($r | upsert suite_id $suite_id)
    }
    if $suite_kind != null and (not ($suite_kind | is-empty)) {
        $r = ($r | upsert suite_kind $suite_kind)
    }

    $r
}
