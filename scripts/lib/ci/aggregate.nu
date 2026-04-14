# CI suite aggregator: reconstruct a single suite-manifest from per-cell
# artifact directories, as if the suite had been a single run.
#
# Each cell's artifacts/.../<exec_id>/meta/suite-manifest.v1.json is read and
# merged into one tree. The aggregated manifest preserves all runs, results,
# cells, flows, and the suite-level index.

use ../run-metadata.nu [utc-now]
use ../publish-envelope.nu []

# Merge two suite-manifest records together (right-biased for top-level fields;
# maps under flows/cells/runs/results/indexes are union-merged).
def merge-manifests [base: record, other: record] {
    let flows = ($base.flows | merge $other.flows)
    let cells = ($base.cells | merge $other.cells)
    let runs = ($base.runs | merge $other.runs)
    let results = ($base.results | merge $other.results)

    # Merge latest_terminal_result_by_cell indexes.
    let base_idx = ($base.indexes?.latest_terminal_result_by_cell? | default {})
    let other_idx = ($other.indexes?.latest_terminal_result_by_cell? | default {})
    let merged_idx = ($base_idx | merge $other_idx)

    $base
        | upsert flows $flows
        | upsert cells $cells
        | upsert runs $runs
        | upsert results $results
        | upsert indexes {latest_terminal_result_by_cell: $merged_idx}
}

# Compute aggregate suite status from individual cell statuses.
# "passed" only when all cells passed.
# "missing" when some cells have no recorded outcome (plan-aware only).
# "blocked" when some are blocked but none actually failed.
# "failed" when at least one actually failed (failed, infra-failed, or cleanup-failed).
# "running" when some cells are still in progress.
export def aggregate-status [statuses: list<string>] {
    if ($statuses | any {|s| (
        ($s == "failed")
        or ($s == "infra-failed")
        or ($s == "cleanup-failed")
    )}) {
        "failed"
    } else if ($statuses | any {|s| $s == "running"}) {
        "running"
    } else if ($statuses | any {|s| $s == "blocked"}) {
        "blocked"
    } else if ($statuses | any {|s| $s == "missing"}) {
        "missing"
    } else if ($statuses | all {|s| $s == "passed"}) {
        "passed"
    } else {
        "unknown"
    }
}

# Read the suite-manifest from a single cell artifact directory.
# Returns null if the manifest is missing (e.g. cell not yet run).
def read-cell-manifest [artifacts_base: string] {
    let path = ($artifacts_base | path join "meta/suite-manifest.v1.json")
    if not ($path | path exists) { null } else { open $path }
}

# Aggregate per-cell suite-manifest files into one suite-level manifest.
# artifact_dirs is a list of absolute paths to per-cell execution directories.
# suite_id: the suite_id to stamp on the output.
# Returns the merged manifest record.
export def aggregate-suite-manifests [
    artifact_dirs: list<string>,
    suite_id: string,
] {
    let generated_at = (utc-now)
    let empty_manifest = {
        schema_version: 1,
        generated_at: $generated_at,
        suite_id: $suite_id,
        producer: {name: "ocmts-aggregator", version: "0.1.0"},
        flows: {},
        cells: {},
        runs: {},
        results: {},
        indexes: {latest_terminal_result_by_cell: {}},
    }

    let manifests = ($artifact_dirs | each {|dir|
        read-cell-manifest $dir
    } | where {|m| $m != null})

    let merged = ($manifests | reduce --fold $empty_manifest {|m, acc|
        merge-manifests $acc $m
    })

    # Compute aggregate status from all results.
    let statuses = ($merged.results | transpose k v | each {|r| $r.v.status? | default "unknown"})
    let agg_status = (aggregate-status $statuses)

    $merged
        | upsert generated_at $generated_at
        | upsert suite_id $suite_id
        | upsert aggregate_status $agg_status
}

# Aggregate per-cell manifests with plan-awareness.
# expected_cell_ids: list of cell_ids that were planned; cells with no manifest
# get a synthetic "missing" result injected into the manifest.
export def aggregate-suite-manifests-plan-aware [
    artifact_dirs: list<string>,
    suite_id: string,
    expected_cell_ids: list<string>,
] {
    let generated_at = (utc-now)
    let base = (aggregate-suite-manifests $artifact_dirs $suite_id)

    # Build synthetic missing results for planned cells with no recorded outcome.
    let found_cell_ids = ($base.results | transpose k v | each {|r| $r.v.cell_id? | default ""})
    let missing_ids = ($expected_cell_ids | where {|id| not ($id in $found_cell_ids)})

    if ($missing_ids | is-empty) {
        return $base
    }

    let missing_results = ($missing_ids | reduce --fold {} {|id, acc|
        let result_id = $"result-missing-($id)"
        $acc | insert $result_id {
            schema_version: 1,
            id: $result_id,
            run_id: "",
            execution_id: "",
            cell_id: $id,
            exit_code: 1,
            status: "missing",
            finished_at: $generated_at,
            failure_reason: "cell had no recorded outcome",
        }
    })

    let merged_results = ($base.results | merge $missing_results)
    let all_statuses = ($merged_results | transpose k v | each {|r| $r.v.status? | default "unknown"})
    let agg_status = (aggregate-status $all_statuses)

    $base
        | upsert results $merged_results
        | upsert aggregate_status $agg_status
        | upsert missing_cell_ids $missing_ids
}

# Compute summary counts from an aggregated manifest.
# Returns a record with total, passed, failed, infra_failed, cleanup_failed,
# blocked, missing, unknown, and aggregate_status.
export def build-aggregate-summary [manifest: record] {
    let statuses = (
        $manifest.results
        | transpose k v
        | each {|r| $r.v.status? | default "unknown"}
    )
    let total = ($statuses | length)
    let passed = ($statuses | where {|s| $s == "passed"} | length)
    let failed = ($statuses | where {|s| $s == "failed"} | length)
    let infra_failed = ($statuses | where {|s| $s == "infra-failed"} | length)
    let cleanup_failed = ($statuses | where {|s| $s == "cleanup-failed"} | length)
    let blocked = ($statuses | where {|s| $s == "blocked"} | length)
    let missing = ($statuses | where {|s| $s == "missing"} | length)
    let known = ($passed + $failed + $infra_failed + $cleanup_failed + $blocked + $missing)
    let unknown = ($total - $known)
    let agg_status = ($manifest.aggregate_status? | default "unknown")
    {
        total: $total,
        passed: $passed,
        failed: $failed,
        infra_failed: $infra_failed,
        cleanup_failed: $cleanup_failed,
        blocked: $blocked,
        missing: $missing,
        unknown: $unknown,
        aggregate_status: $agg_status,
    }
}

# Write summary.json and summary.md derived from a manifest into output_dir.
def write-summary-files [manifest: record, output_dir: string] {
    let s = (build-aggregate-summary $manifest)
    $s | to json --indent 2 | save --force ($output_dir | path join "summary.json")
    let md = ([
        "# Aggregate Suite Summary"
        ""
        $"aggregate_status: ($s.aggregate_status)"
        ""
        "| status | count |"
        "| --- | --- |"
        $"| total | ($s.total) |"
        $"| passed | ($s.passed) |"
        $"| failed | ($s.failed) |"
        $"| infra_failed | ($s.infra_failed) |"
        $"| cleanup_failed | ($s.cleanup_failed) |"
        $"| blocked | ($s.blocked) |"
        $"| missing | ($s.missing) |"
        $"| unknown | ($s.unknown) |"
    ] | str join "\n")
    $md | save --force ($output_dir | path join "summary.md")
}

# Create a zstd-compressed tar archive of the artifacts directory.
# Returns the archive path. Fails clearly if tar/zstd are unavailable.
# archive_name: filename for the archive (default: suite-artifacts.tar.zst).
# Writes to a temp file first to avoid archiving the output file itself
# when output_dir is inside artifacts_root.
export def create-suite-archive [
    artifacts_root: string,
    output_dir: string,
    --archive-name: string = "suite-artifacts.tar.zst",
] {
    let out_path = ($output_dir | path join $archive_name)
    let tar_check = (try {
        ^tar --version | complete
    } catch {
        {exit_code: 127, stdout: "", stderr: "tar not found"}
    })
    if $tar_check.exit_code != 0 {
        error make {msg: "create-suite-archive: tar is required but not available"}
    }
    let zstd_check = (try {
        ^zstd --version | complete
    } catch {
        {exit_code: 127, stdout: "", stderr: "zstd not found"}
    })
    if $zstd_check.exit_code != 0 {
        error make {msg: "create-suite-archive: zstd is required but not available"}
    }
    # Write to a temp path outside the tree so the archive file is never
    # included in its own contents (self-archival race when output_dir
    # is under artifacts_root).
    let tmp_path = (^mktemp | str trim)
    let result = (try {
        ^tar -c -C ($artifacts_root | path dirname) ($artifacts_root | path basename)
            | ^zstd -o $tmp_path
        | complete
    } catch {|e|
        {exit_code: 1, stdout: "", stderr: $e.msg}
    })
    if $result.exit_code != 0 {
        try { ^rm -f $tmp_path } catch {}
        error make {msg: $"create-suite-archive: archive creation failed: ($result.stderr)"}
    }
    mkdir $output_dir
    ^mv $tmp_path $out_path
    $out_path
}

# Write an aggregated suite manifest to a destination directory.
# Also writes derived summary.json and summary.md.
# Returns the path to the suite-manifest.v1.json file.
export def write-aggregated-suite-manifest [
    artifact_dirs: list<string>,
    suite_id: string,
    output_dir: string,
    --expected-cell-ids: list<string> = [],
] {
    mkdir $output_dir
    let manifest = if not ($expected_cell_ids | is-empty) {
        aggregate-suite-manifests-plan-aware $artifact_dirs $suite_id $expected_cell_ids
    } else {
        aggregate-suite-manifests $artifact_dirs $suite_id
    }
    let path = ($output_dir | path join "suite-manifest.v1.json")
    $manifest | to json --indent 2 | save --force $path
    write-summary-files $manifest $output_dir
    $path
}

# Reconstruct suite index files from an aggregated manifest.
# Writes <artifacts_root>/suites/runs/<suite_id>.json and LATEST_SUITE_ID.
# Run entries are built from manifest results, enriched with cell and run data,
# so blocked and missing cells are included alongside passed/failed ones.
# Returns the suite record path, or null if suite_id is not a valid shape.
export def reconstruct-suite-index [
    manifest: record,
    artifacts_root: string,
] {
    let suite_id = ($manifest.suite_id? | default "")
    # Require the standard YYYYMMDDtHHMMSS-<8hex> shape used by new-suite-id.
    if ($suite_id | str contains "..") {
        return null
    }
    if not ($suite_id =~ '^\d{8}t\d{6}-[0-9a-f]{8}$') {
        return null
    }

    let generated_at = ($manifest.generated_at? | default (utc-now))
    let agg_status = ($manifest.aggregate_status? | default "unknown")
    let suite_status = match $agg_status {
        "passed" => "passed"
        "failed" => "failed"
        "blocked" => "blocked"
        "missing" => "blocked"
        "running" => "running"
        _ => "failed"
    }

    # Collect all cell_ids observed in cells map and results.
    let cell_ids_from_cells = ($manifest.cells | transpose k v | each {|r| $r.k})
    let cell_ids_from_results = (
        $manifest.results
        | transpose k v
        | each {|r| $r.v.cell_id? | default ""}
        | where {|id| not ($id | is-empty)}
    )
    let scheduled_cells = (
        $cell_ids_from_cells | append $cell_ids_from_results | uniq | sort
    )

    # Build run entries from results so blocked and missing cells are present.
    let run_entries = ($manifest.results | transpose k v | each {|r|
        let res = $r.v
        let cell_id = ($res.cell_id? | default "")
        let cell_info = ($manifest.cells | get --optional $cell_id | default {})
        let exec_id = ($res.execution_id? | default ($res.run_id? | default ""))
        let run_id = ($res.run_id? | default "")
        let run_info = if ($run_id | is-empty) {
            {}
        } else {
            ($manifest.runs | get --optional $run_id | default {})
        }
        {
            flow_id: ($cell_info.flow_id? | default ""),
            pair: ($cell_info.pair? | default ""),
            execution_id: $exec_id,
            cell_id: $cell_id,
            artifact_name: ($cell_info.artifact_name? | default ""),
            status: ($res.status? | default "unknown"),
            exit_code: ($res.exit_code? | default 0),
            started_at: ($run_info.started_at? | default $generated_at),
            finished_at: ($res.finished_at? | default $generated_at),
        }
    })

    let statuses = ($run_entries | each {|e| $e.status})
    let passed_count = ($statuses | where {|s| $s == "passed"} | length)
    let failed_count = ($statuses | where {|s| (
        ($s == "failed") or ($s == "infra-failed") or ($s == "cleanup-failed")
    )} | length)
    let blocked_count = ($statuses | where {|s| (
        ($s == "blocked") or ($s == "missing")
    )} | length)

    let suite_record = {
        schema_version: 2,
        suite_id: $suite_id,
        suite_kind: "aggregated",
        started_at: $generated_at,
        finished_at: $generated_at,
        status: $suite_status,
        scheduled_cells: $scheduled_cells,
        runs: $run_entries,
        passed_count: $passed_count,
        failed_count: $failed_count,
        blocked_count: $blocked_count,
    }

    let suites_dir = ($artifacts_root | path join "suites")
    let runs_dir = ($suites_dir | path join "runs")
    mkdir $runs_dir
    let record_path = ($runs_dir | path join $"($suite_id).json")
    $suite_record | to json --indent 2 | save --force $record_path
    $suite_id | save --force ($suites_dir | path join "LATEST_SUITE_ID")
    $record_path
}
