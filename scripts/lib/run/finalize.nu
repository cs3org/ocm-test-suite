# Shared run finalization helper.
#
# Callers must not treat raw Cypress exit as the final verdict for the last step.
# This helper computes the resolved verdict from Cypress exit plus post-flow
# validators, writes meta/run.json via write-terminal-run, then writes the
# consolidated meta/result.v1.json with the embedded verdict block.
#
# To inject a validator report in tests, pass --validator-report with a non-null
# record of the same shape dispatch-validators returns. Pass nothing (or null)
# to trigger live auto-dispatch.
#
# Validator report shape:
#   {
#     validators:         list<string>  - names of validators that ran
#     override_outcome:   string | null - "passed" | "failed" | null (null = keep base)
#     override_exit_code: int | null    - explicit exit for override; null = derive from status
#     notes:              list<string>  - diagnostic strings
#   }

use ./metadata.nu [write-terminal-run]
use ../mitm/validator-dispatcher.nu [dispatch-validators]
use ../publish/envelope.nu [detect-execution-context collect-evidence]
use ../publish/evidence.nu [emit-evidence]

# Compute final verdict, write all terminal metadata, return resolved exit code.
#
# stage is the flow stage this call represents; supported values:
#   "after-cypress"  - called right after Cypress run, before teardown
#   "after-down"     - called after teardown is complete (most callers)
#
# Exit code rules:
#   - No validator override: final exit == cypress_exit (exact value preserved)
#   - Validator override with override_exit_code set: final exit == override_exit_code
#   - Validator override without override_exit_code: final exit derived from override status
#
# Inject --validator-report for testing or explicit override paths; omit (null)
# for production where the dispatcher runs live.
export def finalize-run [
    artifacts_base: string,
    execution_id: string,
    cell_id: string,
    artifact_name: string,
    started_at: string,
    finished_at: string,
    stack_id: string,
    cypress_exit: int,
    stage: string,
    images: any = null,
    --suite-id: string = "",
    --suite-kind: string = "",
    --validator-report: any = null,
] {
    let base_status = if $cypress_exit == 0 { "passed" } else { "failed" }
    let base = {status: $base_status, exit_code: $cypress_exit}

    let report = if $validator_report != null {
        $validator_report
    } else {
        dispatch-validators $artifacts_base $stage $base_status
    }

    let override_status = ($report.override_outcome? | default null)

    let final_status = if $override_status != null { $override_status } else { $base_status }

    let final_exit = if $override_status != null {
        # Validator override path: use explicit exit code when provided.
        let ov_exit = ($report.override_exit_code? | default null)
        if $ov_exit != null {
            $ov_exit
        } else if $final_status == "passed" {
            0
        } else {
            1
        }
    } else {
        # No override: preserve exact Cypress exit code (e.g. 3, 7, 127).
        $cypress_exit
    }

    let final = {status: $final_status, exit_code: $final_exit}
    let validators = ($report.validators? | default [])

    (write-terminal-run $artifacts_base $execution_id $cell_id $artifact_name
        $started_at $finished_at $final_status $final_exit $stack_id $images
        --suite-id $suite_id --suite-kind $suite_kind)

    let ctx = (detect-execution-context)
    let ev = (collect-evidence $artifacts_base)
    let verdict = {
        stage: $stage,
        base: $base,
        final: $final,
        validators: $validators,
    }
    mut r = {
        schema_version: 1,
        id: $"result-($execution_id)",
        run_id: $execution_id,
        execution_id: $execution_id,
        cell_id: $cell_id,
        artifact_name: $artifact_name,
        started_at: $started_at,
        finished_at: $finished_at,
        status: $final_status,
        exit_code: $final_exit,
        verdict: $verdict,
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
    }
    if not ($suite_id | is-empty) { $r = ($r | upsert suite_id $suite_id) }
    if not ($suite_kind | is-empty) { $r = ($r | upsert suite_kind $suite_kind) }
    $r | to json --indent 2 | save --force ($artifacts_base | path join "meta/result.v1.json")

    try {
        emit-evidence $artifacts_base $cell_id $execution_id
    } catch {|e|
        print --stderr $"WARNING: evidence sidecar emit failed: ($e.msg)"
    }

    $final_exit
}
