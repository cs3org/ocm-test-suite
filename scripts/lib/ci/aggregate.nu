# CI suite aggregator: reconstruct a single suite-manifest from per-cell
# artifact directories, as if the suite had been a single run.
#
# Each cell's artifacts/.../<exec_id>/meta/suite-manifest.v1.json is read and
# merged into one tree. The aggregated manifest preserves all runs, results,
# cells, flows, and the suite-level index.

use ../time/utc.nu [utc-now]
use ../run/status.nu [run-status-precedence]
use ../run/result-envelope.nu [build-result-v1]
use ../schema/validate.nu [assert-schema-version]
use ./zstd.nu [build-zstd-flags default_zstd_archive_policy]

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
# "passed" only when all cells passed or capability-skipped.
# "missing" when some cells have no recorded outcome (plan-aware only).
# "blocked" when some are blocked but none actually failed.
# "failed" when at least one actually failed (failed, infra-failed, or cleanup-failed).
# "running" when some cells are still in progress.
# capability-skipped cells are transparent to status computation.
# Delegates to run-status-precedence (SSOT in scripts/lib/run/status.nu).
export def aggregate-status [statuses: list<string>] {
    run-status-precedence $statuses
}

# Read the suite-manifest from a single cell artifact directory.
# Returns null if the manifest is missing (e.g. cell not yet run).
def read-cell-manifest [artifacts_base: string] {
    let path = ($artifacts_base | path join "meta/suite-manifest.v1.json")
    if not ($path | path exists) { return null }
    let doc = (open $path)
    assert-schema-version $doc 1 $path
    $doc
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
# capability_skipped_cells: subset of planned cells that are capability-skipped
# (each record has at least cell_id, flow_id, pair, artifact_name, scenario,
# sender_platform, sender_version, receiver_platform, receiver_version,
# is_two_party, execution_id, and capability_skip.rationale).
# Those cells get a "capability-skipped" result instead of "missing", and their
# cells/flows map entries are synthesized from the record fields.
export def aggregate-suite-manifests-plan-aware [
    artifact_dirs: list<string>,
    suite_id: string,
    expected_cell_ids: list<string>,
    --capability-skipped-cells: list<record> = [],
] {
    let generated_at = (utc-now)
    let base = (aggregate-suite-manifests $artifact_dirs $suite_id)

    # Build a lookup map keyed by cell_id for fast access.
    let cap_skipped_map = ($capability_skipped_cells | reduce --fold {} {|cell, acc|
        $acc | insert $cell.cell_id $cell
    })

    # Build synthetic results for planned cells with no recorded outcome.
    let found_cell_ids = ($base.results | transpose k v | each {|r| $r.v.cell_id? | default ""})
    let missing_ids = ($expected_cell_ids | where {|id| not ($id in $found_cell_ids)})

    if ($missing_ids | is-empty) {
        return $base
    }

    # Synthesize cells map entries for cap-skipped cells with no manifest.
    let cap_skipped_missing_ids = ($missing_ids | where {|id|
        ($cap_skipped_map | get --optional $id) != null
    })
    let extra_cells = ($cap_skipped_missing_ids | reduce --fold {} {|id, acc|
        let r = ($cap_skipped_map | get --optional $id)
        $acc | insert $id {
            schema_version: 1,
            id: $id,
            flow_id: ($r.flow_id? | default ""),
            pair: ($r.pair? | default ""),
            artifact_name: ($r.artifact_name? | default ""),
            matrix_key: ($r.matrix_key? | default ""),
            sender_platform: ($r.sender_platform? | default ""),
            sender_version: ($r.sender_version? | default ""),
            receiver_platform: ($r.receiver_platform? | default ""),
            receiver_version: ($r.receiver_version? | default ""),
            browser: ($r.browser? | default "chrome"),
            is_two_party: ($r.is_two_party? | default false),
        }
    })

    # Synthesize runs entries for cap-skipped cells with a real execution_id.
    # Includes envelope-rich fields (attempt_number, lifecycle_status, etc.) to match
    # the shape produced by emit-capability-skipped-cell-artifact in ci/blocker.nu.
    let extra_runs = ($cap_skipped_missing_ids | reduce --fold {} {|id, acc|
        let r = ($cap_skipped_map | get --optional $id)
        let exec_id = ($r.execution_id? | default "")
        if ($exec_id | is-empty) {
            $acc
        } else {
            $acc | insert $exec_id {
                schema_version: 1,
                id: $exec_id,
                execution_id: $exec_id,
                cell_id: $id,
                artifact_name: ($r.artifact_name? | default ""),
                matrix_key: ($r.matrix_key? | default ""),
                attempt_number: 1,
                retry_of_run_id: null,
                superseded_by_run_id: null,
                lifecycle_status: "completed",
                started_at: $generated_at,
                finished_at: $generated_at,
                status: "capability-skipped",
                exit_code: 0,
                execution_context: {capability_skipped: true},
                evidence: [],
                warnings: [],
            }
        }
    })

    # Synthesize flows entries for flow_ids not already present.
    let existing_flow_ids = ($base.flows | columns)
    let new_flow_ids = ($cap_skipped_missing_ids | each {|id|
        ($cap_skipped_map | get --optional $id).flow_id? | default ""
    } | where {|fid| (not ($fid | is-empty)) and (not ($fid in $existing_flow_ids))} | uniq)
    let extra_flows = ($new_flow_ids | reduce --fold {} {|fid, acc|
        $acc | insert $fid {schema_version: 1, id: $fid}
    })

    let missing_results = ($missing_ids | reduce --fold {} {|id, acc|
        let cap_rec = ($cap_skipped_map | get --optional $id)
        let is_cap_skipped = ($cap_rec != null)
        let exec_id = if $is_cap_skipped { ($cap_rec.execution_id? | default "") } else { "" }
        let result_id = if $is_cap_skipped {
            $"result-capability-skipped-($id)"
        } else {
            $"result-missing-($id)"
        }
        let failure_reason = if $is_cap_skipped {
            ($cap_rec.capability_skip?.rationale? | default "")
        } else {
            "cell had no recorded outcome"
        }
        # For synthesized records with no real execution, use result_id as a
        # stable synthetic run_id/execution_id so build-result-v1 validates.
        let eff_run_id = if ($exec_id | is-empty) { $result_id } else { $exec_id }
        let cap_skip = if $is_cap_skipped { ($cap_rec.capability_skip? | default null) } else { null }
        let cap_mk = if $is_cap_skipped { ($cap_rec.matrix_key? | default "") } else { "" }
        let result_rec = (build-result-v1 {
            id: $result_id,
            run_id: $eff_run_id,
            execution_id: $eff_run_id,
            cell_id: $id,
            exit_code: (if $is_cap_skipped { 0 } else { 1 }),
            status: (if $is_cap_skipped { "capability-skipped" } else { "missing" }),
            finished_at: $generated_at,
            evidence: [],
            warnings: [],
            failure_reason: (if ($failure_reason | is-empty) { null } else { $failure_reason }),
            capability_skip: $cap_skip,
            matrix_key: (if ($cap_mk | is-empty) { null } else { $cap_mk }),
        })
        $acc | insert $result_id $result_rec
    })

    let merged_cells = ($base.cells | merge $extra_cells)
    let merged_flows = ($base.flows | merge $extra_flows)
    let merged_runs = ($base.runs | merge $extra_runs)
    let merged_results = ($base.results | merge $missing_results)
    let all_statuses = ($merged_results | transpose k v | each {|r| $r.v.status? | default "unknown"})
    let agg_status = (aggregate-status $all_statuses)

    let truly_missing = ($missing_ids | where {|id|
        ($cap_skipped_map | get --optional $id) == null
    })

    $base
        | upsert results $merged_results
        | upsert cells $merged_cells
        | upsert flows $merged_flows
        | upsert runs $merged_runs
        | upsert aggregate_status $agg_status
        | upsert missing_cell_ids $truly_missing
}

# Compute summary counts from an aggregated manifest.
# Returns a record with total, passed, failed, infra_failed, cleanup_failed,
# blocked, missing, capability_skipped, unknown, and aggregate_status.
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
    let capability_skipped = ($statuses | where {|s| $s == "capability-skipped"} | length)
    let known = ($passed + $failed + $infra_failed + $cleanup_failed + $blocked + $missing + $capability_skipped)
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
        capability_skipped: $capability_skipped,
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
        $"| capability_skipped | ($s.capability_skipped) |"
        $"| unknown | ($s.unknown) |"
    ] | str join "\n")
    $md | save --force ($output_dir | path join "summary.md")
}

# Create a zstd-compressed tar archive of the artifacts directory.
# Returns the archive path. Fails clearly if tar/zstd are unavailable.
# archive_name: filename for the archive (default: suite-artifacts.tar.zst).
# zstd_policy: compression tuning record with level, threads, checksum fields.
#   Defaults to default_zstd_archive_policy when null.
# Writes to a temp file first to avoid archiving the output file itself
# when output_dir is inside artifacts_root.
export def create-suite-archive [
    artifacts_root: string,
    output_dir: string,
    --archive-name: string = "suite-artifacts.tar.zst",
    --zstd-policy: any = null,
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
    let eff_policy = ($zstd_policy | default $default_zstd_archive_policy)
    let zstd_flags = (build-zstd-flags $eff_policy)
    # Write to a temp path outside the tree so the archive file is never
    # included in its own contents (self-archival race when output_dir
    # is under artifacts_root).
    let tmp_path = (^mktemp | str trim)
    let result = (try {
        ^tar -c -C ($artifacts_root | path dirname) ($artifacts_root | path basename)
            | ^zstd -f ...$zstd_flags -o $tmp_path
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
    --capability-skipped-cells: list<record> = [],
] {
    mkdir $output_dir
    let manifest = if not ($expected_cell_ids | is-empty) {
        (aggregate-suite-manifests-plan-aware $artifact_dirs $suite_id $expected_cell_ids
            --capability-skipped-cells $capability_skipped_cells)
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
        "missing" => "missing"
        "running" => "running"
        "unknown" => "unknown"
        "capability-skipped" => "capability-skipped"
        _ => {
            error make {msg: $"reconstruct-suite-index: unknown aggregate status '($agg_status)'; expected one of: passed, failed, blocked, missing, running, unknown, capability-skipped"}
        }
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
    let capability_skipped_count = ($statuses | where {|s| $s == "capability-skipped"} | length)

    # schema_version: 2 - suite record format (suites/runs/<suite_id>.json).
    # Distinct from suite-manifest.v1.json which uses schema_version: 1.
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
        capability_skipped_count: $capability_skipped_count,
    }

    let suites_dir = ($artifacts_root | path join "suites")
    let runs_dir = ($suites_dir | path join "runs")
    mkdir $runs_dir
    let record_path = ($runs_dir | path join $"($suite_id).json")
    $suite_record | to json --indent 2 | save --force $record_path
    $suite_id | save --force ($suites_dir | path join "LATEST_SUITE_ID")
    $record_path
}
