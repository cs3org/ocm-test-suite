# Post-run artifact collection: service logs, MITM summaries, and video normalization.
# Best-effort: warns on individual failures but does not throw.

use ../compose/logs.nu [collect-service-logs]
use ../mitm/summary.nu [summarize-mitm-flows]
use ../mitm/ocm-summary.nu [write-ocm-mitm-summaries]

# Read cell_id from meta/cell.json; returns "" when missing or unreadable.
def read-cell-id-from-meta [artifacts_base: string] {
    let cell_json = ($artifacts_base | path join "meta" "cell.json")
    if not ($cell_json | path exists) { return "" }
    try { (open $cell_json).cell_id? | default "" } catch { "" }
}

# Move the first generated spec video to cypress/videos/<cell_id>--run.mp4,
# removing the legacy source so only one video represents this cell.
# Skips when: cell_id is empty, videos dir absent, no mp4s found.
# When target already exists, removes any other .mp4 files best-effort.
# When target is absent, moves the first sorted .mp4 to target, then removes extras.
# Best-effort: warns on individual failures but does not throw.
export def normalize-cypress-video [
    artifacts_base: string,
    cell_id: string,
] {
    if ($cell_id | is-empty) { return }
    let videos_dir = ($artifacts_base | path join "cypress" "videos")
    if not ($videos_dir | path exists) { return }
    let target_name = $"($cell_id)--run.mp4"
    let target_path = ($videos_dir | path join $target_name)
    if ($target_path | path exists) {
        let extras = (try {
            glob $"($videos_dir)/*.mp4"
            | where {|p| (($p | path type) == "file") and ($p != $target_path)}
        } catch { [] })
        for extra in $extras {
            try {
                rm $extra
                print --stderr $"Removed extra video: ($extra | path basename)"
            } catch {|e|
                print --stderr $"WARNING: could not remove extra video: ($e.msg)"
            }
        }
        return
    }
    let mp4s = (try {
        glob $"($videos_dir)/*.mp4"
        | where {|p| ($p | path type) == "file"}
        | sort
    } catch { [] })
    if ($mp4s | is-empty) { return }
    let src = ($mp4s | first)
    try {
        mv $src $target_path
        print --stderr $"Normalized video: ($src | path basename) -> ($target_name)"
    } catch {|e|
        print --stderr $"WARNING: video normalization failed: ($e.msg)"
        return
    }
    let remaining = ($mp4s | skip 1)
    for leftover in $remaining {
        try {
            rm $leftover
            print --stderr $"Removed extra video: ($leftover | path basename)"
        } catch {|e|
            print --stderr $"WARNING: could not remove extra video: ($e.msg)"
        }
    }
}

# Collect service logs and (for two-party runs) MITM flow summaries.
export def collect-run-artifacts [
    artifacts_base: string,
    stack_id: string,
    run_files: list<string>,
    is_two_party: bool,
] {
    let log_services = if $is_two_party {
        ["sender" "sender-db" "sender-cache" "receiver" "receiver-db" "receiver-cache" "mitm"]
    } else {
        ["sender" "sender-db" "sender-cache"]
    }

    try {
        let log_result = (collect-service-logs $artifacts_base $stack_id $run_files $log_services)
        if not $log_result.ok {
            let failed_svcs = (
                $log_result.services
                | where {|s| not $s.ok}
                | each {|s| $s.service}
                | str join ", "
            )
            print --stderr $"WARNING: docker log collection failed for services: ($failed_svcs)"
            let warn_lines = (
                $log_result.services
                | where {|s| not $s.ok}
                | each {|s| $"($s.service): ($s.error? | default 'unknown')"}
                | str join "\n"
            )
            try {
                $warn_lines | save --force ($artifacts_base | path join "meta/docker-log-warning.txt")
            } catch {|se| print --stderr $"WARNING: could not write docker-log-warning.txt: ($se.msg)" }
        }
    } catch {|e|
        print --stderr $"WARNING: docker log collection threw an error: ($e.msg)"
    }

    if $is_two_party {
        try {
            summarize-mitm-flows $artifacts_base
        } catch {|e|
            print --stderr $"WARNING: MITM summary failed: ($e.msg)"
        }
        try {
            write-ocm-mitm-summaries $artifacts_base
        } catch {|e|
            print --stderr $"WARNING: OCM MITM summary failed: ($e.msg)"
        }
    }

    let vid_cell_id = (read-cell-id-from-meta $artifacts_base)
    try {
        normalize-cypress-video $artifacts_base $vid_cell_id
    } catch {|e|
        print --stderr $"WARNING: video normalization error: ($e.msg)"
    }
}
