# Post-run artifact collection: service logs and MITM summaries.
# Best-effort: warns on individual failures but does not throw.

use ../docker-logs.nu [collect-service-logs]
use ../mitm-summary.nu [summarize-mitm-flows]
use ../mitm-ocm-summary.nu [write-ocm-mitm-summaries]

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
            print $"WARNING: docker log collection failed for services: ($failed_svcs)"
            let warn_lines = (
                $log_result.services
                | where {|s| not $s.ok}
                | each {|s| $"($s.service): ($s.error? | default 'unknown')"}
                | str join "\n"
            )
            try {
                $warn_lines | save --force ($artifacts_base | path join "meta/docker-log-warning.txt")
            } catch {|se| print $"WARNING: could not write docker-log-warning.txt: ($se.msg)" }
        }
    } catch {|e|
        print $"WARNING: docker log collection threw an error: ($e.msg)"
    }

    if $is_two_party {
        try {
            summarize-mitm-flows $artifacts_base
        } catch {|e|
            print $"WARNING: MITM summary failed: ($e.msg)"
        }
        try {
            write-ocm-mitm-summaries $artifacts_base
        } catch {|e|
            print $"WARNING: OCM MITM summary failed: ($e.msg)"
        }
    }
}
