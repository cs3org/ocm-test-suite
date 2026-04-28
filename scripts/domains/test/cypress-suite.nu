# Run the full enabled matrix suite sequentially.

use ../../lib/domain/core/ocmts-root.nu [get-ocmts-root]
use ../../lib/matrix/rules-gen.nu [load-matrix-rules]
use ../../lib/site/clone.nu [resolve-site-dir, site-dir-is-local]
use ../../lib/site/publish.nu [run-site-publish]
use ../../lib/site/preview.nu [run-site-preview]
use ../../lib/ci/planner.nu [plan-suite]
use ../../lib/ci/blocker.nu [eval-blocked-cells emit-blocked-cell-artifact]
use ../../lib/ci/suite-stop-on-fail.nu [stop-on-fail-tail]
use ../../lib/ci/flow-order.nu [sort-cells-by-flow-order]
use ../../lib/suite/index.nu [new-suite-id init-suite-record update-latest-suite-id finish-suite-record record-skipped-run]
use ../../lib/run/metadata.nu [utc-now]
use ../../lib/images/resolve.nu [resolve-media-optimizer-image]
use ../../lib/artifacts/optimize-media.nu [optimize-cell-media]
use ../../lib/artifacts/aggregate-optimized-media.nu [aggregate-optimized-media-cells]
use ../../lib/artifacts/optimizer-probe.nu [probe-optimizer-image]

# Run the full enabled matrix suite sequentially via `services up run`.
# Uses the shared CI planner to assign execution_ids and compute prerequisite
# dependencies. When a cell fails, downstream dependent cells are marked
# `blocked` and skipped - no Docker stack is started for them.
# Default: continue after failures.
# Pass --publish-site to push results into the site after the suite finishes.
# Use --site-dir <path> to point at a local worktree instead of cloning
# (requires --publish-site).
# Pass --preview (requires --publish-site) to start a local preview server
# after a successful publish. Blocks until Ctrl+C.
# When --publish-site is set and --skip-optimize is NOT set, the suite
# automatically runs per-cell media optimization and aggregation before
# publishing, so site publish can receive the optimized media aggregate.
# Pass --skip-optimize to disable auto-optimization (site publish will
# hard-fail if the manifest contains media rows).
def main [
    --suite-id: string = "",  # Override generated suite_id for this run
    --stop-on-fail,           # Stop on first failure (default: continue)
    --continue-on-fail,       # Compat alias: continue after failures (now the default)
    --max: int = 0,           # Limit runs to N cells (0 = unlimited)
    --verbose,                # Pass --verbose to services up run
    --publish-site,           # Publish site after suite finalization
    --site-dir: string = "",  # Local site worktree path (requires --publish-site; skips clone/fetch)
    --preview,                # Start preview server after successful publish (requires --publish-site)
    --preview-host: string = "localhost",  # Preview server host (requires --preview)
    --preview-port: int = 4321,            # Preview server port (requires --preview)
    --skip-optimize,          # Skip auto-optimize+aggregate; site publish will fail if media rows exist
] {
    if (not ($site_dir | is-empty)) and (not $publish_site) {
        error make {msg: "--site-dir requires --publish-site"}
    }
    if $preview and (not $publish_site) {
        error make {msg: "--preview requires --publish-site (preview serves the published artifacts)"}
    }
    if $publish_site and (not ($site_dir | is-empty)) {
        let resolved = (resolve-site-dir $site_dir)
        if not ($resolved | path exists) {
            error make {msg: $"--site-dir path does not exist: ($resolved)"}
        }
    }

    let root = get-ocmts-root
    let rules = (load-matrix-rules $root)
    let prereqs = open ($root | path join "config/ci/prerequisites.nuon")
    let workflows_cfg = open ($root | path join "config/ci/workflows.nuon")
    let ocmts_script = ($root | path join "scripts/ocmts.nu")

    let plan = (plan-suite $rules $prereqs)
    let planned_cells = (sort-cells-by-flow-order $plan.cells $workflows_cfg.github.job_order)

    let cells_to_run = if $max > 0 {
        $planned_cells | first $max
    } else {
        $planned_cells
    }
    let total = ($cells_to_run | length)

    if $total == 0 {
        print "Suite: no enabled cells to run."
        return
    }

    let eff_suite_id = if ($suite_id | is-empty) { $plan.suite_id } else { $suite_id }
    print $"Suite: ($total) cell\(s\) to run  suite_id=($eff_suite_id)"

    let cell_ids = ($cells_to_run | each {|c| $c.cell_id})
    (init-suite-record $eff_suite_id "suite" $cell_ids)

    mut passed = 0
    mut failed_cells: list<string> = []
    mut blocked_cells: list<string> = []
    mut skipped_cells: list<string> = []

    for cell in $cells_to_run {
        # Evaluate whether this cell is blocked by a prior failure or a prior block.
        # Both failed and blocked cells are unavailable for downstream dependency
        # checks so transitive blocks propagate correctly.
        let snap_unavailable = ($failed_cells | append $blocked_cells)
        let block_eval = (eval-blocked-cells [$cell] $snap_unavailable)
        let block_entry = ($block_eval | first)

        if $block_entry.blocked {
            print $"\n--- ($cell.cell_id) [BLOCKED: ($block_entry.failure_reason)] ---"
            try {
                (emit-blocked-cell-artifact $root $cell $block_entry.failure_reason
                    --suite-id $eff_suite_id --suite-kind "suite")
            } catch {|e|
                print $"WARNING: emit-blocked-cell-artifact failed: ($e.msg)"
            }
            $blocked_cells = ($blocked_cells | append $cell.cell_id)
            continue
        }

        print $"\n--- ($cell.cell_id) ---"
        mut args: list<string> = [
            "services" "up" "run"
            "--scenario" $cell.scenario
            "--sender-platform" $cell.sender_platform
            "--sender-version" $cell.sender_version
            "--browser" $cell.browser
            "--suite-id" $eff_suite_id
            "--suite-kind" "suite"
            "--execution-id" $cell.execution_id
        ]
        if not ($cell.receiver_platform | is-empty) {
            $args = ($args | append ["--receiver-platform" $cell.receiver_platform])
        }
        if not ($cell.receiver_version | is-empty) {
            $args = ($args | append ["--receiver-version" $cell.receiver_version])
        }
        if $verbose {
            $args = ($args | append ["--verbose"])
        }

        let cell_exit = (try { ^nu $ocmts_script ...$args; 0 } catch {|e| ($e.exit_code? | default 1) })

        if $cell_exit == 0 {
            $passed = $passed + 1
        } else {
            $failed_cells = ($failed_cells | append $cell.cell_id)
            if $stop_on_fail {
                print $"\nStopped on failure: ($cell.cell_id)"
                # All unexecuted tail cells become skipped - including cells that
                # would have been blocked. Stop-on-fail is a local execution halt,
                # not a dependency evaluation; skipped is the correct semantic here.
                let remaining = (stop-on-fail-tail $cells_to_run $cell.cell_id)
                let skipped_at = (utc-now)
                for tail_cell in $remaining {
                    $skipped_cells = ($skipped_cells | append $tail_cell.cell_id)
                    record-skipped-run $eff_suite_id $tail_cell $skipped_at
                }
                break
            }
        }
    }

    let failed_count = ($failed_cells | length)
    let blocked_count = ($blocked_cells | length)
    let skipped_count = ($skipped_cells | length)
    try {
        finish-suite-record $eff_suite_id $passed $failed_count $blocked_count $skipped_count
    } catch {|e|
        print $"WARNING: finish-suite-record failed: ($e.msg)"
    }
    if $max == 0 {
        update-latest-suite-id $eff_suite_id
    }

    let ran = $passed + $failed_count
    print "\n=== Suite Summary ==="
    print $"suite_id:        ($eff_suite_id)"
    print $"Total scheduled: ($total)"
    print $"Ran:             ($ran)"
    print $"Passed:          ($passed)"
    print $"Failed:          ($failed_count)"
    print $"Blocked:         ($blocked_count)"
    if $skipped_count > 0 {
        print $"Skipped:         ($skipped_count)"
    }

    if not ($blocked_cells | is-empty) {
        print "\nBlocked cells:"
        for c in $blocked_cells {
            print $"  - ($c)"
        }
    }
    if not ($skipped_cells | is-empty) {
        print "\nSkipped cells:"
        for c in $skipped_cells {
            print $"  - ($c)"
        }
    }
    if not ($failed_cells | is-empty) {
        print "\nFailing cells:"
        for c in $failed_cells {
            print $"  - ($c)"
        }
    }

    let eff_site_dir = if $publish_site {
        if not ($site_dir | is-empty) {
            resolve-site-dir $site_dir
        } else {
            let env_dir = ($env.OCM_WEB_SITE_DIR? | default "")
            if not ($env_dir | is-empty) {
                print --stderr $"cypress-suite: auto-resolved --site-dir to ($env_dir)"
                $env_dir
            } else {
                let root = get-ocmts-root
                let computed = (($root | path dirname) | path join "ocm-web-site")
                print --stderr $"cypress-suite: auto-resolved --site-dir to ($computed)"
                $computed
            }
        }
    } else {
        $site_dir
    }
    let skip_clone = (site-dir-is-local $site_dir)
    mut publish_exit = 0
    if $publish_site {
        let optimized_media_dir = if (not $skip_optimize) {
            print "\n=== Optimizing cell media ==="
            let work_dir = ($nu.temp-path | path join $"ocmts-cypress-suite-optimize-($eff_suite_id)")
            let result = (try {
                run-suite-optimize-aggregate $cells_to_run $root $work_dir
            } catch {|e|
                print $"ERROR: media optimization failed: ($e.msg)"
                print $"  work dir preserved at: ($work_dir)"
                null
            })
            if $result == null {
                $publish_exit = 1
                ""
            } else {
                $result
            }
        } else {
            ""
        }

        if $publish_exit == 0 {
            print "\n=== Publishing site ==="
            $publish_exit = (try {
                run-site-publish $eff_site_dir "" $skip_clone "" $eff_suite_id false $optimized_media_dir
                0
            } catch {|e|
                print $"ERROR: site publish failed: ($e.msg)"
                1
            })
        }
    }

    if $preview and ($failed_cells | is-empty) and ($publish_exit == 0) {
        print "\n=== Starting site preview ==="
        run-site-preview $eff_site_dir $preview_host $preview_port
    }

    if (not ($failed_cells | is-empty)) or ($publish_exit != 0) {
        exit 1
    }
}

# Run per-cell media optimization and aggregate into one bundle.
# Creates work_dir with cells/ and aggregate/ subdirs.
# Returns the aggregate output directory path, or errors on probe failure.
def run-suite-optimize-aggregate [
    cells_to_run: list<record>,
    root: string,
    work_dir: string,
]: nothing -> string {
    let cells_work = ($work_dir | path join "cells")
    let agg_work = ($work_dir | path join "aggregate")
    mkdir $cells_work
    mkdir $agg_work

    let image = (resolve-media-optimizer-image)
    let probe = (probe-optimizer-image $image)
    if not $probe.ok {
        let missing_enc = ($probe.encoders | items {|k v| if not $v { $k } else { null }} | where {|x| $x != null} | str join ", ")
        let missing_mux = ($probe.muxers | items {|k v| if not $v { $k } else { null }} | where {|x| $x != null} | str join ", ")
        error make {msg: (
            $"run-suite-optimize-aggregate: optimizer probe failed for ($image): "
            + (if not ($missing_enc | is-empty) { $"missing encoders: ($missing_enc); " } else { "" })
            + (if not ($missing_mux | is-empty) { $"missing muxers: ($missing_mux)" } else { "" })
        )}
    }

    print $"  optimizer image: ($image)"
    print $"  work dir: ($work_dir)"

    mut optimized_cell_dirs = []

    for cell in $cells_to_run {
        let exec_id = ($cell.execution_id? | default "")
        if ($exec_id | is-empty) {
            print $"  skip ($cell.cell_id): no execution_id"
            continue
        }
        let flow_id = ($cell.flow_id? | default "")
        let pair = ($cell.pair? | default "")
        let run_dir = ($root | path join "artifacts" $flow_id $pair $exec_id)
        if not ($run_dir | path exists) {
            print $"  skip ($cell.cell_id): run dir not found at ($run_dir)"
            continue
        }

        # Build staging dir by copying only the publishable cypress subtrees
        # (screenshots and videos). Symlinks cannot be used here: nu's glob
        # does not recurse into symlinked directories, and Docker bind mounts
        # cannot read through host symlinks pointing at host-absolute paths.
        let staging = ($cells_work | path join $cell.cell_id "staging")
        let staging_run_dir = ($staging | path join "artifacts" $flow_id $pair $exec_id)
        let staging_cypress = ($staging_run_dir | path join "cypress")
        mkdir $staging_cypress

        let src_screens = ($run_dir | path join "cypress/screenshots")
        if ($src_screens | path exists) {
            let cp_result = (try {
                ^cp -R $src_screens ($staging_cypress | path join "screenshots") | complete
            } catch {|e| {exit_code: 1, stderr: $e.msg}})
            if $cp_result.exit_code != 0 {
                error make {msg: $"run-suite-optimize-aggregate: copy failed ($src_screens) -> staging: ($cp_result.stderr)"}
            }
        }

        let src_videos = ($run_dir | path join "cypress/videos")
        if ($src_videos | path exists) {
            let cp_result = (try {
                ^cp -R $src_videos ($staging_cypress | path join "videos") | complete
            } catch {|e| {exit_code: 1, stderr: $e.msg}})
            if $cp_result.exit_code != 0 {
                error make {msg: $"run-suite-optimize-aggregate: copy failed ($src_videos) -> staging: ($cp_result.stderr)"}
            }
        }

        let opt_cell_out = ($cells_work | path join $cell.cell_id "optimized")
        let t_start = (date now)
        try {
            optimize-cell-media $staging $opt_cell_out $image
        } catch {|e|
            print $"  WARNING: optimize-cell-media failed for ($cell.cell_id): ($e.msg)"
        }
        let elapsed_ms = ((date now) - $t_start | into int) / 1_000_000
        print $"  optimized ($cell.cell_id) in ($elapsed_ms)ms"

        $optimized_cell_dirs = ($optimized_cell_dirs | append $opt_cell_out)
    }

    if ($optimized_cell_dirs | is-empty) {
        print "  no cells produced optimized media; creating empty aggregate placeholder"
        let fake_cell = ($cells_work | path join "empty-cell")
        mkdir ($fake_cell | path join "meta")
        {
            schema_version: 1,
            generated_at: (date now | date to-timezone "UTC" | format date "%Y-%m-%dT%H:%M:%SZ"),
            status: "no-source-media",
            optimizer_image: $image,
            items: [],
        } | to json --indent 2 | save --force ($fake_cell | path join "meta/optimized-media-cell.v1.json")
        $optimized_cell_dirs = [$fake_cell]
    }

    let result = (aggregate-optimized-media-cells $optimized_cell_dirs $agg_work --no-archive)
    print $"  aggregate: ($result.optimized_item_count) items optimized, ($result.failed_item_count) failed, ($result.cells_with_media) cells with media"
    print $"  aggregate dir: ($agg_work)"

    $agg_work
}
