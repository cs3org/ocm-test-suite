# Canonical run-status precedence logic shared by aggregate.nu and suite/index.nu.
# Single SSOT for status priority ordering across CI aggregation and suite tracking.

# Compute the most severe status from a list of status strings.
# Precedence (highest to lowest): failed/infra-failed/cleanup-failed > running
#   > blocked > missing > passed (capability-skipped is transparent).
# Empty list -> "passed" (vacuous truth via all).
export def run-status-precedence [statuses: list<string>]: nothing -> string {
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
    } else if ($statuses | all {|s| ($s == "passed") or ($s == "capability-skipped")}) {
        "passed"
    } else {
        "unknown"
    }
}
