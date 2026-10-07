# Shared readiness reason codes. Providers supply their own codes, sort
# sequence, and role names. Unknown codes collapse to readiness-check so
# monitor text cannot leak.

export const CORE_REASON_ORDER = [
    "process-count"
    "not-running"
    "unhealthy"
    "restarts"
    "hostname-mismatch"
    "image-mismatch"
    "missing-ip"
    "duplicate-ip"
    "monitor-unavailable"
    "timeout"
    "evidence-write"
    "readiness-check"
]

# `order`, when set, is the caller's full sort sequence. Otherwise core
# codes sort first and `extra` codes follow.
export def order-reasons [
    reasons: list<string>,
    extra: list<string> = [],
    --order: list<string> = [],
] {
    let uniq = ($reasons | uniq)
    if not ($order | is-empty) {
        let known = ($order | where {|code| $code in $uniq})
        let tail = ($uniq | where {|code| not ($code in $order)})
        return ($known | append $tail)
    }
    let known = ($CORE_REASON_ORDER | where {|code| $code in $uniq})
    let mid = ($extra | where {|code|
        ($code in $uniq) and (not ($code in $CORE_REASON_ORDER))
    })
    let tail = ($uniq | where {|code|
        (not ($code in $CORE_REASON_ORDER)) and (not ($code in $extra))
    })
    $known | append $mid | append $tail
}

export def safe-reason [
    code: string,
    known: list<string>,
    roles: list<string> = [],
] {
    if $code in $known {
        return $code
    }
    let parts = ($code | split row ":")
    if ($parts | length) == 2 {
        let role = ($parts | first)
        let tail = ($parts | last)
        if ($role in $roles) and ($tail in $known) {
            return $code
        }
    }
    "readiness-check"
}

export def prefix-reasons [
    role: string,
    reasons: list<string>,
    --order: list<string> = [],
] {
    let ordered = (order-reasons $reasons --order $order)
    $ordered | each {|code| $"($role):($code)"}
}

export def fail-readiness [
    label: string,
    reasons: list<string>,
    known: list<string>,
    roles: list<string> = [],
] {
    let codes = if ($reasons | is-empty) {
        ["timeout"]
    } else {
        $reasons | each {|code| safe-reason $code $known $roles} | uniq
    }
    let joined = ($codes | str join ", ")
    error make {msg: $"($label) failed: ($joined)"}
}
