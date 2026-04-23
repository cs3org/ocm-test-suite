# Stage-aware post-flow validator dispatcher.
#
# Supported stages: after-cypress, after-down.
# Unknown stages return the noop report.
#
# Returns a merged report record:
#   validators:         list<string>  - names of validators that ran
#   override_outcome:   string | null - "passed" | "failed" | null (null = keep base)
#   override_exit_code: int | null    - explicit exit code; null = derive from status
#   notes:              list<string>  - diagnostic strings from validators

use ./code-flow-validator.nu [run-after-down]

def noop-report [] {
    {validators: [], override_outcome: null, override_exit_code: null, notes: []}
}

# Merge individual validator reports into one output record.
#
# Merge rules:
#   - validator names and notes are concatenated
#   - if any report forces "failed", merged override is "failed"
#   - else if base outcome is "failed" and any report forces "passed",
#     merged override is "passed"
#   - else override is null
#   - winning override exit code: prefer any explicit (non-null) override_exit_code
#     from a report in the winning group; fall back to 1 (failed) or 0 (passed);
#     null when there is no override; order-insensitive in mixed explicit/null batches
export def merge-validator-reports [
    reports: list,
    base_outcome: string,
] {
    let all_validators = ($reports | each {|r| $r.validators? | default []} | flatten)
    let all_notes = ($reports | each {|r| $r.notes? | default []} | flatten)
    let failed_reports = ($reports | where {|r| $r.override_outcome? == "failed"})
    let passed_reports = ($reports | where {|r| $r.override_outcome? == "passed"})
    let any_failed = (not ($failed_reports | is-empty))
    let any_passed = (not ($passed_reports | is-empty))

    let override_outcome = if $any_failed {
        "failed"
    } else if ($base_outcome == "failed" and $any_passed) {
        "passed"
    } else {
        null
    }

    # Winning override exit code: prefer any explicit (non-null) override_exit_code
    # from a report in the winning group; fall back to derived value (1 for failed,
    # 0 for passed); null when there is no override. Filtering for explicit values
    # before selecting makes this order-insensitive in mixed explicit/null batches.
    let override_exit_code = if $any_failed {
        let explicit = ($failed_reports | where {|r| $r.override_exit_code? != null})
        if not ($explicit | is-empty) {
            ($explicit | first).override_exit_code
        } else {
            1
        }
    } else if ($base_outcome == "failed" and $any_passed) {
        let explicit = ($passed_reports | where {|r| $r.override_exit_code? != null})
        if not ($explicit | is-empty) {
            ($explicit | first).override_exit_code
        } else {
            0
        }
    } else {
        null
    }

    {
        validators: $all_validators,
        override_outcome: $override_outcome,
        override_exit_code: $override_exit_code,
        notes: $all_notes,
    }
}

# Dispatch post-flow validators for the given stage and return a merged report.
#
# Reads meta/cell.json from artifacts_base when present to resolve the flow_id
# for after-down dispatch. Missing or malformed cell.json degrades gracefully
# to flow_id = null, which returns the noop report.
export def dispatch-validators [
    artifacts_base: string,
    stage: string,        # "after-cypress" or "after-down"
    base_outcome: string, # "passed" or "failed"
] {
    match $stage {
        "after-cypress" => (noop-report),
        "after-down" => {
            let cell_path = ($artifacts_base | path join "meta/cell.json")
            let flow_id = if ($cell_path | path exists) {
                try {
                    let cell = (open $cell_path)
                    $cell.flow_id? | default null
                } catch {
                    null
                }
            } else {
                null
            }

            let reports = match $flow_id {
                "code-flow" => [(run-after-down $artifacts_base $base_outcome)],
                _ => [],
            }

            if ($reports | is-empty) {
                noop-report
            } else {
                merge-validator-reports $reports $base_outcome
            }
        },
        _ => (noop-report),
    }
}
