# Artifacts domain: artifact inspection and log collection.

use ../../lib/cell.nu [compute-cell validate-cell-rules]
use ../../lib/artifacts-init.nu [read-last-execution-id]
use ../../lib/execution-id.nu [validate-execution-id validate-artifact-name execution-artifacts-path]
use ../../lib/domain/core/ocmts-root.nu [get-ocmts-root]
use ../../lib/compose-validate.nu [validate-compose-strict]
use ../../lib/docker-logs.nu [collect-service-logs]
use ../../lib/services/compose-files.nu [read-active-compose-files]
use ../../lib/publish-envelope.nu [emit-publish-envelope]
use ../../lib/artifacts-prune.nu [
    resolve-latest-for-artifact
    run-passes-safety-filters
    collect-scoped-runs
    plan-run-deletion
    apply-run-deletion
]

def main [] {
    print "Usage: nu scripts/ocmts.nu artifacts <verb> [flags]"
    print ""
    print "Verbs:"
    print "  list     List artifact runs for a cell"
    print "  show     Show metadata for a run"
    print "  collect  Collect artifacts for a run (use --include-logs for docker logs)"
    print "  publish  Regenerate suite-manifest.v1.json, summary.json, summary.md"
    print "  prune    Prune run directories or evidence files across artifact runs"
    print "           Default mode (runs): deletes entire run dirs except the latest."
    print "           Evidence mode (--mode evidence): deletes videos/logs and republishes."
}

def "main list" [
    --scenario: string,
    --sender-platform: string,
    --sender-version: string,
    --receiver-platform: string = "",
    --receiver-version: string = "",
] {
    let root = get-ocmts-root
    let flow_id = (validate-cell-rules
        $scenario $sender_platform $sender_version "chrome"
        $receiver_platform $receiver_version)
    let cell = (compute-cell
        $scenario $sender_platform $sender_version "chrome"
        $receiver_platform $receiver_version $flow_id)
    let safe_name = (validate-artifact-name $cell.artifact_name)
    let base = ($root | path join "artifacts" $safe_name)
    if not ($base | path exists) {
        print $"No artifacts found for ($cell.artifact_name)"
        return
    }
    ls $base | where type == dir | sort-by modified --reverse | each {|row|
        let exec_id = ($row.name | path basename)
        let valid_id = (try { validate-execution-id $exec_id; true } catch { false })
        if not $valid_id {
            {execution_id: $exec_id, modified: $row.modified, status: "invalid-id", exit_code: ""}
        } else {
            let result_file = ($row.name | path join "meta/result.json")
            if ($result_file | path exists) {
                let r = (open $result_file)
                {
                    execution_id: $exec_id,
                    modified: $row.modified,
                    status: ($r.status? | default ""),
                    exit_code: ($r.exit_code? | default ""),
                }
            } else {
                {execution_id: $exec_id, modified: $row.modified, status: "", exit_code: ""}
            }
        }
    }
}

def "main show" [
    --scenario: string,
    --sender-platform: string,
    --sender-version: string,
    --receiver-platform: string = "",
    --receiver-version: string = "",
    --execution-id: string = "",
] {
    let root = get-ocmts-root
    let flow_id = (validate-cell-rules
        $scenario $sender_platform $sender_version "chrome"
        $receiver_platform $receiver_version)
    let cell = (compute-cell
        $scenario $sender_platform $sender_version "chrome"
        $receiver_platform $receiver_version $flow_id)
    let exec_id = if ($execution_id | is-empty) {
        read-last-execution-id $cell.artifact_name
    } else {
        $execution_id
    }
    let base = (execution-artifacts-path $root $cell.artifact_name $exec_id)
    let result_file = ($base | path join "meta/result.json")
    let run_file = ($base | path join "meta/run.json")
    mut summary = {artifacts_base: $base}
    if ($run_file | path exists) { $summary = ($summary | upsert run (open $run_file)) }
    if ($result_file | path exists) { $summary = ($summary | upsert result (open $result_file)) }
    if ($summary | reject artifacts_base | is-empty) {
        error make {msg: $"No metadata found for execution_id=($exec_id)"}
    }
    $summary
}

def "main collect" [
    --scenario: string,
    --sender-platform: string,
    --sender-version: string,
    --receiver-platform: string = "",
    --receiver-version: string = "",
    --execution-id: string = "",
    --include-logs,
] {
    let root = get-ocmts-root
    let flow_id = (validate-cell-rules
        $scenario $sender_platform $sender_version "chrome"
        $receiver_platform $receiver_version)
    let cell = (compute-cell
        $scenario $sender_platform $sender_version "chrome"
        $receiver_platform $receiver_version $flow_id)
    let exec_id = if ($execution_id | is-empty) {
        read-last-execution-id $cell.artifact_name
    } else {
        $execution_id
    }
    let base = (execution-artifacts-path $root $cell.artifact_name $exec_id)

    let stack_id_file = ($base | path join "compose" "stack_id.txt")
    if not ($stack_id_file | path exists) {
        error make {msg: $"No stack_id found for execution_id=($exec_id). Artifacts may be missing."}
    }
    let stack_id = (open --raw $stack_id_file | str trim)

    if not $include_logs {
        print "Hint: pass --include-logs to collect docker service logs."
        print $"Artifacts: ($base)"
        return
    }

    # Determine expected services for this topology.
    let log_services = if $cell.is_two_party {
        ["sender" "sender-db" "sender-cache" "receiver" "receiver-db" "receiver-cache" "mitm"]
    } else {
        ["sender" "sender-db" "sender-cache"]
    }

    # If all expected logs already exist (e.g., collected during `services up run`),
    # report them and skip live docker collection.
    let logs_dir = ($base | path join "docker" "logs")
    let expected_paths = ($log_services | each {|svc|
        {service: $svc, path: ($logs_dir | path join $"($svc).log")}
    })
    let all_cached = ($expected_paths | all {|e| $e.path | path exists})
    if $all_cached {
        $expected_paths | each {|e| print $"Collected: ($e.path)"}
        return
    }

    # Some or all logs are missing; attempt live collection.
    let base_yml = ($root | path join "config/compose/base.yml")
    let compose_files = (read-active-compose-files $base $base_yml)

    # Optional: validate compose file set before collecting logs.
    let logs_resolved_path = ($base | path join "compose" "compose.resolved.logs.yml")
    try {
        validate-compose-strict $compose_files $stack_id $logs_resolved_path
    } catch {|e|
        print $"WARNING: compose validation before log collection failed: ($e.msg)"
    }

    let result = (collect-service-logs $base $stack_id $compose_files $log_services)
    $result.services | each {|s|
        if ($s.skipped? | default false) {
            let note = ($s.note? | default "SKIPPED")
            print $"Skipped: ($s.service) - ($note)"
        } else if $s.ok {
            print $"Collected: ($s.path)"
        } else {
            let err = ($s.error? | default "unknown")
            print $"FAILED: ($s.service) - ($err)"
        }
    }
    if not $result.ok {
        # If the stack is gone (teardown already ran), surface which logs are
        # missing and explain that live collection is no longer possible.
        let stack_gone = ($result.services | any {|s|
            ((not $s.ok)
                and (($s.error? | default "") | str contains "no containers"))
        })
        if $stack_gone {
            let missing = ($expected_paths | where {|e| not ($e.path | path exists)})
            let missing_list = ($missing | each {|e| $"  ($e.path)"} | str join "\n")
            error make {msg: $"Log collection failed: stack is already torn down. Missing logs:\n($missing_list)"}
        } else {
            error make {msg: "Log collection failed for one or more services. See output above."}
        }
    }
}

# Regenerate suite-manifest.v1.json, summary.json, summary.md for a run.
# Pass --artifacts-base with the full path to the execution artifact root,
# e.g. artifacts/<artifact_name>/<execution_id>.
def "main publish" [
    --artifacts-base: string,
    --scenario: string = "",
    --sender-platform: string = "",
    --sender-version: string = "",
    --receiver-platform: string = "",
    --receiver-version: string = "",
    --execution-id: string = "",
] {
    # If --artifacts-base is given, use it directly.
    let base = if not ($artifacts_base | is-empty) {
        $artifacts_base
    } else {
        let root = get-ocmts-root
        let flow_id = (validate-cell-rules
            $scenario $sender_platform $sender_version "chrome"
            $receiver_platform $receiver_version)
        let cell = (compute-cell
            $scenario $sender_platform $sender_version "chrome"
            $receiver_platform $receiver_version $flow_id)
        let exec_id = if ($execution_id | is-empty) {
            read-last-execution-id $cell.artifact_name
        } else {
            $execution_id
        }
        execution-artifacts-path $root $cell.artifact_name $exec_id
    }
    if not ($base | path exists) {
        error make {msg: $"Artifacts base not found: ($base)"}
    }
    emit-publish-envelope $base
    print $"Published envelope for ($base)"
    print $"  meta/suite-manifest.v1.json"
    print $"  meta/summary.json"
    print $"  meta/summary.md"
}

# Prune run directories or evidence files across artifact runs.
# Default mode (runs): deletes entire run directories except the latest.
# Evidence mode (--mode evidence): deletes videos/logs inside run dirs and
# republishes the envelope.
# Default: dry-run, non-latest scope, terminal runs only.
# Pass --apply to delete; --all to target every artifact; or cell selectors
# to target one artifact. --artifacts-base targets a single run dir directly.
def "main prune" [
    --all,                              # target all artifact names
    --artifacts-base: string = "",      # target exactly one run directory
    --scenario: string = "",
    --sender-platform: string = "",
    --sender-version: string = "",
    --receiver-platform: string = "",
    --receiver-version: string = "",
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

    # Resolve target run_bases depending on selector.
    let run_bases = if not ($artifacts_base | is-empty) {
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
        # All artifact names under artifacts/.
        let artifacts_dir = ($root | path join "artifacts")
        if not ($artifacts_dir | path exists) {
            []
        } else {
            let artifact_names = (
                ls $artifacts_dir
                | where type == dir
                | each {|row| $row.name | path basename}
            )
            $artifact_names | each {|name|
                collect-scoped-runs $root $name $eff_scope $published_only $include_nonterminal
            } | flatten
        }
    } else {
        # Cell selector target.
        if ($scenario | is-empty) {
            error make {msg: (
                "Provide --all, --artifacts-base, or cell selectors "
                + "(--scenario, --sender-platform, --sender-version)"
            )}
        }
        let flow_id = (validate-cell-rules
            $scenario $sender_platform $sender_version "chrome"
            $receiver_platform $receiver_version)
        let cell = (compute-cell
            $scenario $sender_platform $sender_version "chrome"
            $receiver_platform $receiver_version $flow_id)
        collect-scoped-runs $root $cell.artifact_name $eff_scope $published_only $include_nonterminal
    }

    let total_runs = ($run_bases | length)

    if $mode == "runs" {
        # Runs mode: delete entire run directories.
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
