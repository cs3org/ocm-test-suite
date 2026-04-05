# Helpers for `artifacts prune`.

use ./execution-id.nu [validate-execution-id]

# Determine the latest execution_id for an artifact_name.
# Prefers LAST_EXECUTION_ID marker when valid and pointing to an existing dir.
# Falls back to the newest valid run dir by mtime.
# Returns null when no valid run dir exists.
export def resolve-latest-for-artifact [root: string, artifact_name: string] {
    let marker = ($root | path join "artifacts" $artifact_name "LAST_EXECUTION_ID")
    if ($marker | path exists) {
        let candidate = (open --raw $marker | str trim)
        let candidate_dir = ($root | path join "artifacts" $artifact_name $candidate)
        let valid = (try { validate-execution-id $candidate; true } catch { false })
        if $valid and ($candidate_dir | path exists) {
            return $candidate
        }
    }
    let artifact_base = ($root | path join "artifacts" $artifact_name)
    if not ($artifact_base | path exists) { return null }
    let dirs = (try {
        ls $artifact_base | where type == dir | sort-by modified --reverse
    } catch { [] })
    let valid_ids = ($dirs | each {|row|
        let id = ($row.name | path basename)
        let ok = (try { validate-execution-id $id; true } catch { false })
        if $ok { $id } else { "" }
    } | where {|id| not ($id | is-empty)})
    if ($valid_ids | is-empty) { null } else { $valid_ids | first }
}

# Check whether a single run_base passes safety filters.
export def run-passes-safety-filters [
    run_base: string,
    published_only: bool,
    include_nonterminal: bool,
] {
    let manifest_path = ($run_base | path join "meta/suite-manifest.v1.json")
    let manifest_ok = (not $published_only) or ($manifest_path | path exists)
    if not $manifest_ok { return false }
    let run_json_path = ($run_base | path join "meta/run.json")
    let terminal_ok = if (not $include_nonterminal) and ($run_json_path | path exists) {
        let run_data = (open $run_json_path)
        let status = ($run_data.status? | default "")
        not ($status in ["prepared" "active" "open"])
    } else {
        true
    }
    $terminal_ok
}

# Collect run_base paths for one artifact that pass scope + safety filters.
export def collect-scoped-runs [
    root: string,
    artifact_name: string,
    scope: string,
    published_only: bool,
    include_nonterminal: bool,
] {
    let artifact_base = ($root | path join "artifacts" $artifact_name)
    if not ($artifact_base | path exists) { return [] }
    let latest_id = (resolve-latest-for-artifact $root $artifact_name)
    let dirs = (try {
        ls $artifact_base | where type == dir | sort-by modified --reverse
    } catch { [] })
    let all_ids = ($dirs | each {|row|
        let id = ($row.name | path basename)
        let ok = (try { validate-execution-id $id; true } catch { false })
        if $ok { $id } else { "" }
    } | where {|id| not ($id | is-empty)})
    let scoped = if $scope == "latest" {
        if $latest_id != null { [$latest_id] } else { [] }
    } else if $scope == "non-latest" {
        $all_ids | where {|id| $id != $latest_id}
    } else if $scope == "all" {
        $all_ids
    } else {
        error make {msg: $"scope must be latest/non-latest/all, got: ($scope)"}
    }
    $scoped | each {|exec_id|
        let run_base = ($root | path join "artifacts" $artifact_name $exec_id)
        let passes = (run-passes-safety-filters $run_base $published_only $include_nonterminal)
        if $passes { $run_base } else { "" }
    } | where {|p| not ($p | is-empty)}
}

# Compute files to delete for a run. Does not modify anything.
export def plan-run-deletion [
    run_base: string,
    drop_videos: bool,
    drop_docker_logs: bool,
] {
    let videos = if $drop_videos {
        try { glob ($run_base | path join "cypress/videos/*.mp4") } catch { [] }
    } else {
        []
    }
    let docker_logs = if $drop_docker_logs {
        try { glob ($run_base | path join "docker/logs/*.log") } catch { [] }
    } else {
        []
    }
    {
        run_base: $run_base,
        videos: $videos,
        docker_logs: $docker_logs,
        total: (($videos | length) + ($docker_logs | length)),
    }
}

# Delete files in a prune plan. Returns the count of deleted files.
# Caller is responsible for republishing when count > 0.
export def apply-run-deletion [plan: record] {
    let all_files = ($plan.videos | append $plan.docker_logs)
    for f in $all_files {
        rm --force $f
    }
    $all_files | length
}
