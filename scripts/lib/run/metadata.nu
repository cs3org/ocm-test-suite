# Per-cell run metadata writers: writes meta/run.json (terminal run record)
# and minimal meta/result.v1.json for error paths.
#
# Lifecycle statuses used in run.json:
#   prepared      - initial state after setup-run-context
#   active        - platform services up and healthy (services up)
#   open          - cypress_dev desktop up (services up open)
#   stopped       - stack torn down cleanly (services down success)
#   down-failed   - teardown failed (services down failure)
#   passed        - Cypress run passed (services up run)
#   failed        - Cypress run failed (services up run)
#   infra-failed  - infrastructure failure before Cypress (services up run)
#   cleanup-failed - teardown failed after Cypress run (services up run)

use ../publish/envelope.nu [detect-execution-context collect-evidence]
use ./result-envelope.nu [build-result-v1]

# Write initial run.json in "prepared" state.
export def write-prepared-run [
    artifacts_base: string,
    execution_id: string,
    cell_id: string,
    artifact_name: string,
    started_at: string,
    stack_id: string,
    --suite-id: string = "",
    --suite-kind: string = "single",
] {
    mut r = {
        schema_version: 1,
        id: $execution_id,
        execution_id: $execution_id,
        cell_id: $cell_id,
        artifact_name: $artifact_name,
        started_at: $started_at,
        status: "prepared",
        stack_id: $stack_id,
        artifacts_dir: $artifacts_base,
        suite_kind: $suite_kind,
    }
    if not ($suite_id | is-empty) { $r = ($r | upsert suite_id $suite_id) }
    $r | to json | save --force ($artifacts_base | path join "meta/run.json")
}

# Write terminal run.json (passed / failed / infra-failed / cleanup-failed).
# Use --phase and --fail-error for infrastructure failures before Cypress.
export def write-terminal-run [
    artifacts_base: string,
    execution_id: string,
    cell_id: string,
    artifact_name: string,
    started_at: string,
    finished_at: string,
    status: string,
    exit_code: int,
    stack_id: string,
    images: any = null,
    --phase: string = "",
    --fail-error: string = "",
    --suite-id: string = "",
    --suite-kind: string = "",
] {
    mut r = {
        schema_version: 1,
        id: $execution_id,
        execution_id: $execution_id,
        cell_id: $cell_id,
        artifact_name: $artifact_name,
        started_at: $started_at,
        finished_at: $finished_at,
        status: $status,
        exit_code: $exit_code,
        stack_id: $stack_id,
        artifacts_dir: $artifacts_base,
        images: $images,
    }
    if not ($phase | is-empty) { $r = ($r | upsert phase $phase) }
    if not ($fail_error | is-empty) { $r = ($r | upsert error $fail_error) }
    if not ($suite_id | is-empty) { $r = ($r | upsert suite_id $suite_id) }
    if not ($suite_kind | is-empty) { $r = ($r | upsert suite_kind $suite_kind) }
    $r | to json | save --force ($artifacts_base | path join "meta/run.json")
}

# Update existing meta/run.json for non-terminal lifecycle transitions.
# No-op when run.json does not exist; callers check before calling when needed.
# Does not write result.v1.json - manual up/open/down do not produce result.v1.json.
#
# Clean statuses (active, open, stopped) must not carry stale error/exit_code
# from prior failure states. Those fields are removed on transition to a clean
# status. Failure statuses (down-failed, etc.) may set error/exit_code via flags.
export def update-run-lifecycle [
    artifacts_base: string,
    status: string,
    --phase: string = "",
    --finished-at: string = "",
    --exit-code: int = (-1),
    --error: string = "",
] {
    let run_path = ($artifacts_base | path join "meta/run.json")
    if not ($run_path | path exists) { return }
    mut r = ((open $run_path) | upsert status $status)
    if not ($phase | is-empty) { $r = ($r | upsert phase $phase) }
    if not ($finished_at | is-empty) { $r = ($r | upsert finished_at $finished_at) }
    let clean_statuses = ["active" "open" "stopped"]
    if ($status in $clean_statuses) {
        # Drop stale failure fields so a successful transition never exposes
        # error or exit_code from a prior down-failed/failed state.
        if "error" in $r { $r = ($r | reject error) }
        if "exit_code" in $r { $r = ($r | reject exit_code) }
    } else {
        if $exit_code >= 0 { $r = ($r | upsert exit_code $exit_code) }
        if not ($error | is-empty) { $r = ($r | upsert error $error) }
    }
    $r | to json | save --force $run_path
}

# Write terminal run.json and the consolidated meta/result.v1.json together
# in one call. The result.v1.json is "minimal": no verdict block (no Cypress
# ran on these error paths). finalize-run overwrites it with a full,
# verdict-aware version on the happy path.
export def write-terminal-outcome [
    artifacts_base: string,
    execution_id: string,
    cell_id: string,
    artifact_name: string,
    started_at: string,
    finished_at: string,
    status: string,
    exit_code: int,
    stack_id: string,
    images: any = null,
    --phase: string = "",
    --fail-error: string = "",
    --suite-id: string = "",
    --suite-kind: string = "",
] {
    (write-terminal-run $artifacts_base $execution_id $cell_id $artifact_name
        $started_at $finished_at $status $exit_code $stack_id $images
        --phase $phase --fail-error $fail_error
        --suite-id $suite_id --suite-kind $suite_kind)

    let ctx = (detect-execution-context)
    let ev = (collect-evidence $artifacts_base)
    let r = (build-result-v1 {
        id: $"result-($execution_id)",
        run_id: $execution_id,
        execution_id: $execution_id,
        cell_id: $cell_id,
        artifact_name: $artifact_name,
        started_at: $started_at,
        finished_at: $finished_at,
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
        suite_id: $suite_id,
        suite_kind: $suite_kind,
    })
    $r | to json --indent 2 | save --force ($artifacts_base | path join "meta/result.v1.json")
}
