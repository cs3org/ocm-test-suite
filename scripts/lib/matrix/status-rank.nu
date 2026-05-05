# Canonical capability/blocker status precedence table.
# Single SSOT for rank ordering imported by blocker-logic, planner, and rules-gen.
# Higher rank = worse status.

export const STATUS_RANK = {
    "supported": 0,
    "placeholder": 1,
    "test-implementation-pending": 2,
    "vendor-unsupported": 3,
    "vendor-out-of-scope": 4,
}

# Return the worst (highest-rank) status from a list of status strings.
# Empty list returns "supported". Unknown status strings error fast.
export def worst-status [statuses: list<string>] {
    if ($statuses | is-empty) { return "supported" }
    let ranked = ($statuses | each {|s|
        let r = ($STATUS_RANK | get --optional $s)
        if $r == null {
            error make {msg: $"worst-status: unknown status '($s)'; expected one of: supported, placeholder, test-implementation-pending, vendor-unsupported, vendor-out-of-scope"}
        }
        $r
    })
    let max_rank = ($ranked | math max)
    $STATUS_RANK | transpose key val | where val == $max_rank | first | get key
}

# Return the worst-status blocker record from a list of blocker records.
# Returns null when the list is empty.
# Blockers without a status field are treated as vendor-unsupported (broken data).
export def pick-worst-blocker [blockers: list] {
    if ($blockers | is-empty) { return null }
    let scored = ($blockers | each {|b|
        let s = ($b.status? | default "vendor-unsupported")
        let r = ($STATUS_RANK | get --optional $s)
        let r = if $r != null { $r } else {
            error make {msg: $"pick-worst-blocker: unknown status '($s)'; expected one of: supported, placeholder, test-implementation-pending, vendor-unsupported, vendor-out-of-scope"}
        }
        {rank: $r, blocker: $b}
    })
    let max_rank = ($scored | get rank | math max)
    ($scored | where rank == $max_rank | first | get blocker)
}
