# Suite index: create, track, and query suite runs.
# Storage contract:
#   artifacts/suites/LATEST_SUITE_ID
#   artifacts/suites/runs/<suite_id>.json

use ../domain/core/ocmts-root.nu [get-ocmts-root]
use ../time/utc.nu [utc-now]

def suites-dir [] {
    (get-ocmts-root) | path join "artifacts/suites"
}

def suite-record-path [suite_id: string] {
    (suites-dir) | path join "runs" $"($suite_id).json"
}

def latest-marker-path [] {
    (suites-dir) | path join "LATEST_SUITE_ID"
}

# Generate a new unique suite_id (same shape as execution_id).
export def new-suite-id [] {
    let ts = (date now | format date "%Y%m%dt%H%M%S")
    let rand = (random uuid | split row '-' | first)
    $"($ts)-($rand)"
}

# Validate suite_id shape: YYYYMMDDtHHMMSS-<8 hex chars>.
# Rejects path traversal and non-conformant shapes.
export def validate-suite-id [suite_id: string] {
    if ($suite_id | str contains "..") {
        error make {msg: $"suite_id path traversal rejected: ($suite_id)"}
    }
    if not ($suite_id =~ '^\d{8}t\d{6}-[0-9a-f]{8}$') {
        error make {msg: $"suite_id shape invalid: ($suite_id)"}
    }
    $suite_id
}

# Create a new suite record in "running" status.
export def init-suite-record [
    suite_id: string,
    suite_kind: string,
    cell_ids: list<string>,
] {
    let safe_id = (validate-suite-id $suite_id)
    let dir = ((suites-dir) | path join "runs")
    mkdir $dir
    # schema_version: 2 - suite record format (suites/runs/<suite_id>.json).
    # Distinct from suite-manifest.v1.json which uses schema_version: 1.
    let record = {
        schema_version: 2,
        suite_id: $safe_id,
        suite_kind: $suite_kind,
        started_at: (utc-now),
        finished_at: "",
        status: "running",
        scheduled_cells: $cell_ids,
        runs: [],
    }
    $record | to json | save --force (suite-record-path $safe_id)
}

# Write the LATEST_SUITE_ID marker file.
export def update-latest-suite-id [suite_id: string] {
    let safe_id = (validate-suite-id $suite_id)
    mkdir (suites-dir)
    $safe_id | save --force (latest-marker-path)
}

# Append a run entry to the suite record (schema v2).
# Errors propagate; use record-suite-run-safe for fire-and-forget calls.
export def record-suite-run [
    suite_id: string,
    flow_id: string,
    pair: string,
    execution_id: string,
    cell_id: string,
    artifact_name: string,
    status: string,
    exit_code: int,
    started_at: string,
    finished_at: string,
] {
    let safe_id = (validate-suite-id $suite_id)
    let path = (suite-record-path $safe_id)
    if not ($path | path exists) {
        error make {msg: $"Suite record not found: ($path)"}
    }
    let rec = (open $path)
    let entry = {
        flow_id: $flow_id,
        pair: $pair,
        execution_id: $execution_id,
        cell_id: $cell_id,
        artifact_name: $artifact_name,
        status: $status,
        exit_code: $exit_code,
        started_at: $started_at,
        finished_at: $finished_at,
    }
    ($rec | upsert runs ($rec.runs | append $entry)) | to json | save --force $path
}

# Append a skipped run entry for a planned cell that was never executed.
# Used by stop-on-fail tail to record unexecuted cells cleanly.
# cell must have flow_id, pair, execution_id, cell_id, artifact_name fields.
export def record-skipped-run [
    suite_id: string,
    cell: record,
    skipped_at: string,
] {
    try {
        (record-suite-run $suite_id
            ($cell.flow_id? | default "")
            ($cell.pair? | default "")
            ($cell.execution_id? | default "")
            $cell.cell_id
            ($cell.artifact_name? | default "")
            "skipped" (-1) "" $skipped_at)
    } catch {|e|
        print $"WARNING: record-skipped-run failed for ($suite_id)/($cell.cell_id): ($e.msg)"
    }
}

# Append a capability-skipped run entry for a planned cell that was excluded due
# to a required capability not being implemented for its platform/version.
# cell must have flow_id, pair, execution_id, cell_id, artifact_name fields.
export def record-capability-skipped-run [
    suite_id: string,
    cell: record,
    skipped_at: string,
] {
    try {
        (record-suite-run $suite_id
            ($cell.flow_id? | default "")
            ($cell.pair? | default "")
            ($cell.execution_id? | default "")
            $cell.cell_id
            ($cell.artifact_name? | default "")
            "capability-skipped" 0 "" $skipped_at)
    } catch {|e|
        print $"WARNING: record-capability-skipped-run failed for ($suite_id)/($cell.cell_id): ($e.msg)"
    }
}

# Safe variant of record-suite-run - prints a warning instead of erroring.
export def record-suite-run-safe [
    suite_id: string,
    flow_id: string,
    pair: string,
    execution_id: string,
    cell_id: string,
    artifact_name: string,
    status: string,
    exit_code: int,
    started_at: string,
    finished_at: string,
] {
    try {
        (record-suite-run $suite_id $flow_id $pair $execution_id $cell_id $artifact_name
            $status $exit_code $started_at $finished_at)
    } catch {|e|
        print $"WARNING: record-suite-run failed for ($suite_id): ($e.msg)"
    }
}

# Compute suite overall status from a list of cell statuses.
# Precedence matches aggregate-status in ci/aggregate.nu: failed > running > blocked > missing > passed.
# capability-skipped cells are transparent (all cap-skipped -> "passed").
export def compute-suite-status [cell_statuses: list<string>] {
    if ($cell_statuses | any {|s| (
        ($s == "failed") or ($s == "infra-failed") or ($s == "cleanup-failed")
    )}) {
        "failed"
    } else if ($cell_statuses | any {|s| $s == "running"}) {
        "running"
    } else if ($cell_statuses | any {|s| $s == "blocked"}) {
        "blocked"
    } else if ($cell_statuses | any {|s| $s == "missing"}) {
        "missing"
    } else if ($cell_statuses | all {|s| ($s == "passed") or ($s == "capability-skipped")}) {
        "passed"
    } else {
        "unknown"
    }
}

# Finalize a suite record: set status, counts, and finished_at.
# blocked defaults to 0 so existing callers without a blocked count still work.
# skipped defaults to 0; skipped count is persisted but does not affect status.
# capability_skipped defaults to 0; does not affect status.
export def finish-suite-record [
    suite_id: string,
    passed: int,
    failed: int,
    blocked: int = 0,
    skipped: int = 0,
    capability_skipped: int = 0,
] {
    let safe_id = (validate-suite-id $suite_id)
    let path = (suite-record-path $safe_id)
    if not ($path | path exists) {
        error make {msg: $"Suite record not found: ($path)"}
    }
    # Build a synthetic status list from counts to feed compute-suite-status.
    let status_list = (
        (0..<$passed | each {"passed"})
        | append (0..<$failed | each {"failed"})
        | append (0..<$blocked | each {"blocked"})
        | append (0..<$skipped | each {"missing"})
        | append (0..<$capability_skipped | each {"capability-skipped"})
    )
    let overall = if ($status_list | is-empty) { "passed" } else { (compute-suite-status $status_list) }
    (open $path)
        | upsert status $overall
        | upsert finished_at (utc-now)
        | upsert passed_count $passed
        | upsert failed_count $failed
        | upsert blocked_count $blocked
        | upsert skipped_count $skipped
        | upsert capability_skipped_count $capability_skipped
        | to json
        | save --force $path
}

# Read a suite record by id.
export def read-suite-record [suite_id: string] {
    let safe_id = (validate-suite-id $suite_id)
    let path = (suite-record-path $safe_id)
    if not ($path | path exists) {
        error make {msg: $"Suite record not found: ($path)"}
    }
    open $path
}

# Read the latest suite_id from the LATEST_SUITE_ID marker.
export def get-latest-suite-id [] {
    let marker = (latest-marker-path)
    if not ($marker | path exists) {
        error make {msg: $"LATEST_SUITE_ID marker not found: ($marker)"}
    }
    (open --raw $marker | str trim)
}

# List all suite records sorted by suite_id descending.
export def list-suite-records [] {
    let dir = ((suites-dir) | path join "runs")
    if not ($dir | path exists) { return [] }
    glob ($dir | path join "*.json")
        | each {|p| open $p}
        | sort-by suite_id --reverse
}

# Resolve and load a suite record from the suites index.
# artifacts_root must be the artifacts/ directory (e.g. <ocmts-root>/artifacts).
# Validates suite_id before path use.
# Returns {suite_id: string, suite_record: record}.
export def load-suite-entry [
    artifacts_root: string,
    explicit_id: string,
    use_latest: bool,
] {
    let eff_id = if $use_latest {
        let marker = ($artifacts_root | path join "suites/LATEST_SUITE_ID")
        if not ($marker | path exists) {
            error make {msg: $"LATEST_SUITE_ID marker not found: ($marker)"}
        }
        (open --raw $marker | str trim)
    } else {
        $explicit_id
    }
    # Validate before path join to reject traversal.
    let safe_id = if ($eff_id | str contains "..") {
        error make {msg: $"suite_id path traversal rejected: ($eff_id)"}
    } else if not ($eff_id =~ '^\d{8}t\d{6}-[0-9a-f]{8}$') {
        error make {msg: $"suite_id shape invalid: ($eff_id)"}
    } else {
        $eff_id
    }
    let suite_path = ($artifacts_root | path join "suites/runs" $"($safe_id).json")
    if not ($suite_path | path exists) {
        error make {msg: $"Suite record not found: ($suite_path)"}
    }
    {suite_id: $safe_id, suite_record: (open $suite_path)}
}
