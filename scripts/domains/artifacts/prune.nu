# Prune run directories or evidence files across artifact runs.
# Default mode (runs): deletes entire run directories except the latest.
# Evidence mode (--mode evidence): deletes videos/logs inside run dirs and
# republishes the envelope.
# Default: dry-run, non-latest scope, terminal runs only.
# Pass --apply to delete; --all to target every artifact; or cell selectors
# to target one artifact. --artifacts-base targets a single run dir directly.
# Suite selection (--suite-id/--latest-suite) targets exactly the runs in a
# suite and cannot be combined with --all, --artifacts-base, or cell selectors.

use ../../lib/matrix/cell.nu [compute-cell validate-cell-rules]
use ../../lib/domain/core/ocmts-root.nu [get-ocmts-root]
use ../../lib/publish/envelope.nu [emit-publish-envelope]
use ../../lib/artifacts/prune.nu [
    run-passes-safety-filters
    collect-scoped-runs
    collect-all-scoped-runs
    plan-run-deletion
    apply-run-deletion
]
use ../../lib/suite/index.nu [load-suite-entry]

def main [
    --all,                              # target all flow+pair combinations (excludes suites/)
    --artifacts-base: string = "",      # target exactly one run directory
    --flow: string = "",
    --sender-platform: string = "",
    --sender-version: string = "",
    --receiver-platform: string = "",
    --receiver-version: string = "",
    --suite-id: string = "",            # target runs from this suite_id only
    --latest-suite,                     # target runs from the latest suite (LATEST_SUITE_ID)
    --apply,                            # perform deletions; default is dry-run
    --scope: string = "non-latest",     # latest | non-latest | all
    --all-latest,                       # with --all: set scope to "all"
    --no-drop-videos,                   # evidence mode: skip cypress/videos/*.mp4
    --no-drop-docker-logs,              # evidence mode: skip docker/logs/*.log
    --no-republish,                     # evidence mode: skip rewriting meta files
    --include-unpublished,              # evidence mode: include runs without manifest
    --include-nonterminal,              # include runs with prepared/active/open status
    --json,                             # emit machine-readable output
    --mode: string = "runs",            # runs | evidence
] {
    let root = get-ocmts-root

    if not ($mode in ["runs" "evidence"]) {
        error make {msg: $"--mode must be runs or evidence. Got: ($mode)"}
    }

    if not ($scope in ["latest" "non-latest" "all"]) {
        error make {msg: $"--scope must be latest, non-latest, or all. Got: ($scope)"}
    }

    # --all-latest only meaningful with --all; it overrides scope to "all".
    let eff_scope = if $all and $all_latest { "all" } else { $scope }

    # Runs mode does not require a suite-manifest (unpublished runs included).
    let published_only = if $mode == "runs" { false } else { not $include_unpublished }

    let suite_active = (not ($suite_id | is-empty)) or $latest_suite

    # Resolve target run_bases depending on selector.
    let run_bases = if $suite_active {
        if $all or (not ($artifacts_base | is-empty)) or (not ($flow | is-empty)) {
            error make {msg: (
                "--suite-id/--latest-suite cannot be combined with "
                + "--all, --artifacts-base, or cell selectors"
            )}
        }
        let arts_dir = ($root | path join "artifacts")
        let loaded = (load-suite-entry $arts_dir $suite_id $latest_suite)
        let suite_record = $loaded.suite_record
        $suite_record.runs | each {|run|
            let run_base = ($root | path join "artifacts" $run.flow_id $run.pair $run.execution_id)
            # Enforce prefix safety before any use.
            let artifacts_tree = ($root | path join "artifacts" | path expand)
            let resolved = ($run_base | path expand)
            if not ($resolved | str starts-with ($artifacts_tree + "/")) {
                print $"WARNING: suite run locator outside artifacts tree, skipping: ($run_base)"
                ""
            } else if not ($run_base | path exists) {
                ""
            } else {
                let passes = (run-passes-safety-filters $run_base $published_only $include_nonterminal)
                if $passes { $run_base } else { "" }
            }
        } | where {|p| not ($p | is-empty)}
    } else if not ($artifacts_base | is-empty) {
        # Direct single-run target.
        let resolved_base = ($artifacts_base | path expand)
        let artifacts_tree = ($root | path join "artifacts" | path expand)
        if not ($resolved_base | str starts-with ($artifacts_tree + "/")) {
            error make {msg: $"--artifacts-base must be under ($artifacts_tree), got: ($resolved_base)"}
        }
        if not ($resolved_base | path exists) {
            error make {msg: $"--artifacts-base not found: ($resolved_base)"}
        }
        let passes = (run-passes-safety-filters $resolved_base $published_only $include_nonterminal)
        if $passes { [$resolved_base] } else { [] }
    } else if $all {
        # All flow+pair combinations under artifacts/ (excludes suites/).
        collect-all-scoped-runs $root $eff_scope $published_only $include_nonterminal
    } else {
        # Cell selector target.
        if ($flow | is-empty) {
            error make {msg: (
                "Provide --all, --artifacts-base, or cell selectors "
                + "(--flow, --sender-platform, --sender-version)"
            )}
        }
        validate-cell-rules $flow $sender_platform $sender_version "chrome" $receiver_platform $receiver_version
        let cell = (compute-cell $flow $sender_platform $sender_version "chrome" $receiver_platform $receiver_version)
        collect-scoped-runs $root $cell.flow_id $cell.pair $eff_scope $published_only $include_nonterminal
    }

    let total_runs = ($run_bases | length)

    if $mode == "runs" {
        # Runs mode: delete entire run directories (prefix-checked).
        let artifacts_tree = ($root | path join "artifacts" | path expand)
        if not $apply {
            if $json {
                print ({
                    mode: "dry-run",
                    prune_mode: "runs",
                    scope: $eff_scope,
                    total_runs: $total_runs,
                    run_bases: $run_bases,
                } | to json)
                return
            }
            print $"DRY RUN -- ($total_runs) run director\(ies\) targeted for deletion"
            for rb in $run_bases {
                print $"  ($rb)"
            }
            if $total_runs == 0 {
                print "  (nothing to delete)"
            }
            return
        }
        mut deleted = 0
        for rb in $run_bases {
            let resolved = ($rb | path expand)
            if not ($resolved | str starts-with ($artifacts_tree + "/")) {
                print $"WARNING: skipping path outside artifacts tree: ($rb)"
                continue
            }
            rm --recursive --force $rb
            $deleted = $deleted + 1
        }
        if $json {
            print ({
                mode: "apply",
                prune_mode: "runs",
                scope: $eff_scope,
                total_runs: $total_runs,
                deleted: $deleted,
            } | to json)
            return
        }
        print $"Deleted ($deleted) run director\(ies\)"
        return
    }

    # Evidence mode: delete videos/logs inside run dirs and republish envelope.
    let drop_videos = not $no_drop_videos
    let drop_docker_logs = not $no_drop_docker_logs
    let republish = not $no_republish

    # Build deletion plans (pure, no mutations).
    let plans = ($run_bases | each {|base|
        plan-run-deletion $base $drop_videos $drop_docker_logs
    })
    let total_files = ($plans | reduce --fold 0 {|p, acc| $acc + $p.total})

    if not $apply {
        if $json {
            print ({
                mode: "dry-run",
                prune_mode: "evidence",
                scope: $eff_scope,
                total_runs: $total_runs,
                total_files: $total_files,
                runs: ($plans | each {|p| {
                    run_base: $p.run_base,
                    videos: ($p.videos | length),
                    docker_logs: ($p.docker_logs | length),
                    total: $p.total,
                }}),
            } | to json)
            return
        }
        print $"DRY RUN -- ($total_runs) runs targeted, ($total_files) files to delete"
        for p in $plans {
            if $p.total > 0 {
                print $"  ($p.run_base)"
                print $"    videos=($p.videos | length)  docker_logs=($p.docker_logs | length)"
            }
        }
        if $total_files == 0 {
            print "  (nothing to delete)"
        }
        return
    }

    # Apply deletions.
    mut deleted = 0
    mut republish_failures = []
    for plan in $plans {
        let n = (apply-run-deletion $plan)
        $deleted = $deleted + $n
        if $republish and $n > 0 {
            let republish_err = (try { emit-publish-envelope $plan.run_base; null } catch {|e| $e.msg })
            if $republish_err != null {
                $republish_failures = ($republish_failures | append $plan.run_base)
                print $"WARNING: republish failed for ($plan.run_base): ($republish_err)"
            }
        }
    }

    if $json {
        print ({
            mode: "apply",
            prune_mode: "evidence",
            scope: $eff_scope,
            total_runs: $total_runs,
            total_files: $deleted,
            runs: ($plans | each {|p| {
                run_base: $p.run_base,
                videos: ($p.videos | length),
                docker_logs: ($p.docker_logs | length),
                total: $p.total,
            }}),
        } | to json)
        return
    }
    print $"Pruned ($deleted) file\(s\) across ($total_runs) run\(s\)"

    if not ($republish_failures | is-empty) {
        let n = ($republish_failures | length)
        let failed_list = ($republish_failures | str join "\n  ")
        error make {msg: $"Prune succeeded but republish failed for ($n) run\(s\):\n  ($failed_list)"}
    }
}
