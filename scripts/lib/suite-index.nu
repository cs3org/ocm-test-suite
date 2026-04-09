# Suite index: create, track, and query suite runs.
# Storage contract:
#   artifacts/suites/LATEST_SUITE_ID
#   artifacts/suites/runs/<suite_id>.json

use ./domain/core/ocmts-root.nu [get-ocmts-root]
use ./run-metadata.nu [utc-now]

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

# Finalize a suite record: set status and finished_at.
export def finish-suite-record [
    suite_id: string,
    passed: int,
    failed: int,
] {
    let safe_id = (validate-suite-id $suite_id)
    let path = (suite-record-path $safe_id)
    if not ($path | path exists) {
        error make {msg: $"Suite record not found: ($path)"}
    }
    let overall = if $failed > 0 { "failed" } else { "passed" }
    (open $path)
        | upsert status $overall
        | upsert finished_at (utc-now)
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
