# Generic two-sample readiness wait. The provider owns identity and parties.
# Phase names are harness-owned; this module only records them.

use ../time/utc.nu [utc-now]
use ../run/readiness-evidence.nu [readiness-evidence-commit]
use ./readiness-reasons.nu [
    CORE_REASON_ORDER
    fail-readiness
    order-reasons
    safe-reason
]

def empty-store [] {
    {
        schema_version: 1,
        execution_id: "",
        run_started_at: "",
        updated_at: "",
        providers: {},
    }
}

def known-codes [extra: list<string>] {
    $CORE_REASON_ORDER | append $extra | uniq
}

def safe-reasons [
    reasons: list<string>,
    known: list<string>,
    extra: list<string>,
    roles: list<string>,
    order: list<string>,
] {
    let safe = if ($reasons | is-empty) {
        ["timeout"]
    } else {
        $reasons | each {|code| safe-reason $code $known $roles} | uniq
    }
    order-reasons $safe $extra --order $order
}

def record-failed [
    artifacts_base: string,
    execution_id: string,
    provider: string,
    phase: string,
    reasons: list<string>,
] {
    let body = {
        status: "failed",
        captured_at: (utc-now),
        reasons: $reasons,
    }
    try {
        readiness-evidence-commit $artifacts_base $execution_id $provider $phase $body
    } catch {
        print "WARNING: readiness evidence write failed"
    }
}

def compose-unusable [ctx: record, files: list<string>] {
    let project = ($ctx.stack_id? | default "" | into string | str trim)
    ($project | is-empty) or ($files | is-empty)
}

export def sample-readiness [
    ctx: record,
    files: list<string>,
    provider: record,
] {
    let cell = ($ctx.cell? | default {})
    let roles = (do $provider.parties $cell)
    try {
        do $provider.sample $ctx $files $roles
    } catch {
        {ok: false, reasons: ["readiness-check"], identity: {}, parties: []}
    }
}

export def wait-readiness [
    ctx: record,
    files: list<string>,
    provider: record,
    --timeout: duration = 120sec,
    --phase: string = "",
] {
    if ($phase | is-empty) {
        error make {msg: "readiness phase is required"}
    }
    let cell = ($ctx.cell? | default {})
    let parties = (do $provider.parties $cell)
    if ($parties | is-empty) {
        return (empty-store)
    }

    let extra = ($provider.reason_codes? | default [])
    let role_names = ($provider.role_names? | default [])
    let order = ($provider.reason_order? | default [])
    let known = (known-codes $extra)
    let label = $"($provider.label) readiness"
    let base = ($ctx.artifacts_base? | default "")
    let exec_id = ($ctx.execution_id? | default "")
    let name = $provider.name

    if (compose-unusable $ctx $files) {
        let reasons = (safe-reasons ["compose-query"] $known $extra $role_names $order)
        record-failed $base $exec_id $name $phase $reasons
        fail-readiness $label $reasons $known $role_names
    }

    let deadline = ((date now) + $timeout)
    let interval = $provider.stability_interval
    mut have_first = false
    mut first_json = ""
    mut first_at = (date now)
    mut last = ["timeout"]

    loop {
        if (date now) >= $deadline {
            let reasons = (safe-reasons $last $known $extra $role_names $order)
            record-failed $base $exec_id $name $phase $reasons
            fail-readiness $label $reasons $known $role_names
        }
        let sample = (sample-readiness $ctx $files $provider)
        let ok = ($sample.ok? | default false)
        if $ok {
            let now = (date now)
            let identity = ($sample.identity? | default {})
            let identity_json = ($identity | to json --raw)
            let same = if $have_first { $identity_json == $first_json } else { false }
            let age = if $have_first { $now - $first_at } else { 0sec }
            if ($have_first and $same and ($age >= $interval)) {
                let body = {
                    status: "passed",
                    captured_at: (utc-now),
                    parties: ($sample.parties? | default []),
                }
                readiness-evidence-commit $base $exec_id $name $phase $body | ignore
                return $body
            }
            if ((not $have_first) or (not $same) or ($age >= $interval)) {
                $first_json = $identity_json
                $first_at = $now
                $last = if ($have_first and (not $same)) {
                    ["samples-disagree"]
                } else {
                    ["timeout"]
                }
                $have_first = true
            } else {
                # Young match: a stale disagreement must not outlive this sample.
                $last = ["timeout"]
            }
        } else {
            $have_first = false
            $last = ($sample.reasons? | default ["readiness-check"])
        }
        let remain = ($deadline - (date now))
        if $remain <= 0sec {
            continue
        }
        let pause = if $remain > 2sec { 2sec } else { $remain }
        sleep $pause
    }
}
