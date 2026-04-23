# Run the full enabled matrix suite sequentially.

use ../../lib/domain/core/ocmts-root.nu [get-ocmts-root]
use ../../lib/site/clone.nu [resolve-site-dir]
use ../../lib/site/publish.nu [run-site-publish]
use ../../lib/site/preview.nu [run-site-preview]
use ../../lib/ci/planner.nu [plan-suite]
use ../../lib/ci/blocker.nu [eval-blocked-cells emit-blocked-cell-artifact]
use ../../lib/ci/suite-stop-on-fail.nu [stop-on-fail-tail]
use ../../lib/ci/flow-order.nu [sort-cells-by-flow-order]
use ../../lib/suite/index.nu [new-suite-id init-suite-record update-latest-suite-id finish-suite-record record-skipped-run]
use ../../lib/run/metadata.nu [utc-now]

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
    let rules = open ($root | path join "config/matrix-rules.nuon")
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
    let skip_clone = not ($site_dir | is-empty)
    mut publish_exit = 0
    if $publish_site {
        print "\n=== Publishing site ==="
        $publish_exit = (try {
            run-site-publish $eff_site_dir "" $skip_clone "" $eff_suite_id false
            0
        } catch {|e|
            print $"ERROR: site publish failed: ($e.msg)"
            1
        })
    }

    if $preview and ($failed_cells | is-empty) and ($publish_exit == 0) {
        print "\n=== Starting site preview ==="
        run-site-preview $eff_site_dir $preview_host $preview_port
    }

    if (not ($failed_cells | is-empty)) or ($publish_exit != 0) {
        exit 1
    }
}
