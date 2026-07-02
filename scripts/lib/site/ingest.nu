# Site ingest orchestrator: aggregates manifests and copies artifacts.
# Data contract: suite-manifest.v1.json and matrix-rules.v1.json written to
# the site public/ dir. Input config from the in-memory matrix rules record
# (see `load-matrix-rules`).

use ../suite/index.nu [load-suite-entry]
use ../ci/aggregate.nu [aggregate-status]
use ../run/result-envelope.nu [build-result-v1]
use ./copy.nu [copy-allowlisted-artifacts]
use ./flow-caps.nu [load-flow-caps]
use ./manifest.nu [build-aggregated-manifest build-matrix-rules-json compute-latest-index]
use ./internal.nu [compute-matrix-cells]
use ../matrix/rules-gen.nu [apply-display-rule build-matrix-not-in-scope-json]

# Main ingest: aggregate manifests, write suite-manifest.v1.json and
# matrix-rules.v1.json, copy artifacts.
# Default: reads LAST_EXECUTION_ID per cell. With --suite-id or --latest-suite,
# reads the suite index and ingests exactly the runs listed there.
export def ingest-site [
    artifacts_root: string,    # e.g. <ocmts-root>/artifacts
    rules: record,             # matrix rules record from load-matrix-rules
    root: string,              # ots-rebooted repo root (resolves adapters path and source info)
    public_dir: string,        # e.g. <site-dir>/public
    --suite-id: string = "",   # ingest runs from this suite_id only
    --latest-suite,            # ingest runs from the latest suite (LATEST_SUITE_ID)
] {
    let cell_list = (compute-matrix-cells $rules)
    let suite_active = (not ($suite_id | is-empty)) or $latest_suite
    mut entries = []
    if $suite_active {
        let loaded = (load-suite-entry $artifacts_root $suite_id $latest_suite)
        let eff_id = $loaded.suite_id
        let suite_record = $loaded.suite_record
        let run_count = ($suite_record.runs | length)
        print --stderr $"Ingest mode: suite suite_id=($eff_id) runs=($run_count)"
        for run in $suite_record.runs {
            let exec_id = ($run.execution_id? | default "")
            let run_status = ($run.status? | default "")
            # Compute manifest path up front to decide whether to synthesize.
            let run_dir = if ($exec_id | is-empty) {
                ""
            } else {
                ($artifacts_root | path join $run.flow_id $run.pair $exec_id)
            }
            let mf_path = if ($run_dir | is-empty) {
                ""
            } else {
                ($run_dir | path join "meta/suite-manifest.v1.json")
            }
            let manifest_on_disk = (not ($mf_path | is-empty)) and ($mf_path | path exists)
            # capability-skipped AND manifest missing: synthesize without disk read.
            # This fires whether exec_id is empty or non-empty; the key signal is
            # that no on-disk artifact exists for this skipped cell.
            if ($run_status == "capability-skipped") and (not $manifest_on_disk) {
                let result_id = $"result-capability-skipped-($run.cell_id)"
                let flow_id = ($run.flow_id? | default "")
                let cap_skip = ($run.capability_skip? | default null)
                # Use exec_id when available; fall back to result_id as synthetic id.
                let eff_run_id = if ($exec_id | is-empty) { $result_id } else { $exec_id }
                let synth_result = (build-result-v1 {
                    id: $result_id,
                    run_id: $eff_run_id,
                    execution_id: $eff_run_id,
                    cell_id: $run.cell_id,
                    status: "capability-skipped",
                    exit_code: 0,
                    finished_at: ($run.finished_at? | default ""),
                    evidence: [],
                    warnings: [],
                    capability_skip: $cap_skip,
                })
                # A minimal run entry is required so build-aggregated-manifest
                # can iterate runs without crashing on an empty map.
                let synth_run = {
                    id: $eff_run_id,
                    execution_id: $eff_run_id,
                    cell_id: $run.cell_id,
                    artifact_name: ($run.artifact_name? | default ""),
                    attempt_number: 1,
                    lifecycle_status: "completed",
                    started_at: ($run.finished_at? | default ""),
                    finished_at: ($run.finished_at? | default ""),
                    status: "capability-skipped",
                    exit_code: 0,
                }
                let synth_manifest = {
                    schema_version: 1,
                    suite_id: $eff_id,
                    execution_context: {},
                    flows: {($flow_id): {id: $flow_id}},
                    cells: {($run.cell_id): {
                        id: $run.cell_id,
                        flow_id: $flow_id,
                        pair: ($run.pair? | default ""),
                        artifact_name: ($run.artifact_name? | default ""),
                        matrix_key: ($run.matrix_key? | default ""),
                        sender_platform: ($run.sender_platform? | default ""),
                        sender_version: ($run.sender_version? | default ""),
                        receiver_platform: ($run.receiver_platform? | default ""),
                        receiver_version: ($run.receiver_version? | default ""),
                        browser: ($run.browser? | default "chrome"),
                        is_two_party: ($run.is_two_party? | default false),
                    }},
                    runs: {($eff_run_id): $synth_run},
                    results: {($result_id): $synth_result},
                    indexes: {latest_terminal_result_by_cell: {($run.cell_id): $result_id}},
                }
                $entries = ($entries | append {
                    manifest: $synth_manifest,
                    run_dir: "",
                    flow_id: $flow_id,
                    pair: ($run.pair? | default ""),
                    artifact_name: ($run.artifact_name? | default ""),
                    exec_id: $exec_id,
                    cell_id: $run.cell_id,
                    result_id: $result_id,
                    finished_at: ($run.finished_at? | default ""),
                })
                continue
            }
            # Skip entries with no execution_id that are not capability-skipped.
            if ($exec_id | is-empty) { continue }
            if not ($mf_path | path exists) {
                print --stderr $"WARNING: no suite-manifest for ($run.flow_id)/($run.pair)/($exec_id), skipping"
                continue
            }
            let m = (open $mf_path)
            let result_id = ($m.results | columns | first)
            let finished_at = ($m.results | get $result_id | get finished_at? | default "")
            $entries = ($entries | append {
                manifest: $m,
                run_dir: $run_dir,
                flow_id: $run.flow_id,
                pair: ($run.pair? | default ""),
                artifact_name: ($run.artifact_name? | default ""),
                exec_id: $exec_id,
                cell_id: $run.cell_id,
                result_id: $result_id,
                finished_at: $finished_at,
            })
        }
    } else {
        for cell in $cell_list {
            let marker = ($artifacts_root | path join $cell.flow_id $cell.pair "LAST_EXECUTION_ID")
            if not ($marker | path exists) { continue }
            let exec_id = (open --raw $marker | str trim)
            let run_dir = ($artifacts_root | path join $cell.flow_id $cell.pair $exec_id)
            let mf_path = ($run_dir | path join "meta/suite-manifest.v1.json")
            if not ($mf_path | path exists) {
                print --stderr $"WARNING: no suite-manifest for ($cell.flow_id)/($cell.pair)/($exec_id), skipping"
                continue
            }
            let m = (open $mf_path)
            let result_id = ($m.results | columns | first)
            let finished_at = ($m.results | get $result_id | get finished_at? | default "")
            $entries = ($entries | append {
                manifest: $m,
                run_dir: $run_dir,
                flow_id: $cell.flow_id,
                pair: $cell.pair,
                artifact_name: $cell.artifact_name,
                exec_id: $exec_id,
                cell_id: $cell.cell_id,
                result_id: $result_id,
                finished_at: $finished_at,
            })
        }
    }

    mkdir $public_dir

    let base_aggregated = (build-aggregated-manifest $entries $root)
    # When suite mode is active, inject missing results from the CI aggregated
    # manifest so that planned-but-unrun cells appear in the site manifest.
    let aggregated = if $suite_active {
        let ci_agg_path = ($artifacts_root | path join "suites/aggregated/suite-manifest.v1.json")
        if ($ci_agg_path | path exists) {
            let ci_agg = (open $ci_agg_path)
            let missing_result_rows = (
                $ci_agg.results
                | transpose k v
                | where {|r| ($r.v.status? | default "") == "missing"}
            )
            if not ($missing_result_rows | is-empty) {
                let missing_rec = ($missing_result_rows | each {|r| {($r.k): $r.v}} | into record)
                let merged_results = ($base_aggregated.results | merge $missing_rec)
                # Pull cells/flows from ci_agg for the missing cell_ids so the
                # site manifest has coherent cells/flows for every result.
                let missing_cell_ids = ($missing_result_rows
                    | each {|r| $r.v.cell_id? | default ""}
                    | where {|id| not ($id | is-empty)})
                let existing_cell_ids = ($base_aggregated.cells | columns)
                let ci_agg_cells = ($ci_agg.cells? | default {})
                let cells_to_add = ($missing_cell_ids
                    | where {|id| not ($id in $existing_cell_ids)}
                    | each {|id|
                        let from_agg = ($ci_agg_cells | get --optional $id)
                        let info = if $from_agg != null {
                            $from_agg
                        } else {
                            let list_match = ($cell_list | where {|c| $c.cell_id == $id})
                            if not ($list_match | is-empty) {
                                let c = ($list_match | first)
                                {
                                    id: $id,
                                    flow_id: ($c.flow_id? | default ""),
                                    pair: ($c.pair? | default ""),
                                    artifact_name: ($c.artifact_name? | default ""),
                                    matrix_key: ($c.matrix_key? | default ""),
                                    sender_platform: ($c.sender_platform? | default ""),
                                    sender_version: ($c.sender_version? | default ""),
                                    receiver_platform: ($c.receiver_platform? | default ""),
                                    receiver_version: ($c.receiver_version? | default ""),
                                    browser: ($c.browser? | default ""),
                                    is_two_party: ($c.is_two_party? | default false),
                                }
                            } else {
                                {id: $id}
                            }
                        }
                        {($id): $info}
                    }
                    | into record)
                let flow_ids_to_add = ($cells_to_add
                    | transpose k v
                    | each {|r| $r.v.flow_id? | default ""}
                    | where {|fid| not ($fid | is-empty)}
                    | uniq)
                let existing_flow_ids = ($base_aggregated.flows | columns)
                let ci_agg_flows = ($ci_agg.flows? | default {})
                let flows_to_add = ($flow_ids_to_add
                    | where {|fid| not ($fid in $existing_flow_ids)}
                    | each {|fid|
                        let info = ($ci_agg_flows | get --optional $fid | default {id: $fid})
                        {($fid): $info}
                    }
                    | into record)
                let merged_cells = ($base_aggregated.cells | merge $cells_to_add)
                let merged_flows = ($base_aggregated.flows | merge $flows_to_add)
                let all_statuses = (
                    $merged_results | transpose k v | each {|r| $r.v.status? | default "unknown"}
                )
                let new_agg_status = (aggregate-status $all_statuses)
                let new_index = (compute-latest-index $merged_results)
                $base_aggregated
                    | upsert results $merged_results
                    | upsert cells $merged_cells
                    | upsert flows $merged_flows
                    | upsert aggregate_status $new_agg_status
                    | upsert indexes {latest_terminal_result_by_cell: $new_index}
            } else {
                $base_aggregated
            }
        } else {
            $base_aggregated
        }
    } else {
        $base_aggregated
    }
    ($aggregated | to json --indent 2
        | save --force ($public_dir | path join "suite-manifest.v1.json"))
    print --stderr $"Wrote suite-manifest.v1.json \(($entries | length) runs\)"

    let ocmts_root = $root
    let cap_map_abs = ($ocmts_root | path join "config/adapters/capabilities.v1.nuon")
    let adapters = if ($cap_map_abs | path exists) {
        (open $cap_map_abs).adapters? | default {}
    } else {
        print --stderr $"WARNING: capability map not found at ($cap_map_abs); display rule will treat all caps as missing"
        {}
    }
    let flow_caps = (load-flow-caps ($root | path join "config/matrix/flows"))

    let matrix_json = (build-matrix-rules-json $rules "config/matrix" $adapters $flow_caps $root)
    ($matrix_json | to json --indent 2
        | save --force ($public_dir | path join "matrix-rules.v1.json"))
    print --stderr $"Wrote matrix-rules.v1.json \(($matrix_json.matrix | length) matrix entries\)"

    # build-matrix-rules-json returns matrix cell list; recompute
    # apply-display-rule here to access the not_in_scope output without
    # widening that API.
    let display_cells = (compute-matrix-cells $rules)
    let display_result = (apply-display-rule $display_cells $adapters $flow_caps)
    let not_in_scope_json = (build-matrix-not-in-scope-json $display_result.not_in_scope $root)
    ($not_in_scope_json | to json --indent 2
        | save --force ($public_dir | path join "matrix-not-in-scope.v1.json"))
    let nis_total = ($display_result.not_in_scope | length)
    print --stderr $"Wrote matrix-not-in-scope.v1.json \(($nis_total) entries\)"

    mut total_files = 0
    for entry in $entries {
        # Synthetic cap-skipped entries have no run_dir; nothing to copy.
        if ($entry.run_dir | is-empty) { continue }
        let dst_base = ($public_dir
            | path join "artifacts" $entry.flow_id $entry.pair $entry.exec_id)
        let count = (copy-allowlisted-artifacts $entry.run_dir $dst_base)
        print --stderr $"  ($entry.flow_id)/($entry.pair)/($entry.exec_id): ($count) files"
        $total_files = $total_files + $count
    }
    print --stderr $"Ingest complete: ($entries | length) runs, ($total_files) artifact files"
}
