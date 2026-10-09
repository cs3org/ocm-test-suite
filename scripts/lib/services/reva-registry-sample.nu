# One CERNBox registry sample: compose judge plus broker monitor.
# Identity excludes volatile counters; the receipt still records them.

use ./records.nu [is-record]
use ./reva-registry-docker.nu [
    compose-ps
    compose-tail
    find-slim
    inspect-ids
    intended-image-ref
    normalize-image-id
    resolved-image-id
    run-capped
]
use ./readiness-reasons.nu [order-reasons prefix-reasons]

def restart-count-reason [count: int] {
    if $count > 0 { ["restarts"] } else { [] }
}

def revad-services [role: string, modes: list<string>] {
    $modes | each {|mode| $"($role)-revad-($mode)"}
}

def broker-service [role: string] {
    $"($role)-revad-registry"
}

def judge-revad [
    services: list<string>,
    ps_rows: list,
    inspected: list,
    image_id: string,
    processes: int,
] {
    mut reasons = []
    mut ips = []
    mut restarts = 0
    mut hostname_ok = true
    mut healthy = true
    mut seen = 0
    for svc in $services {
        let matches = ($ps_rows | where {|row| $row.service == $svc})
        if ($matches | length) != 1 {
            $reasons = ($reasons | append "process-count")
            continue
        }
        let slim = (find-slim $inspected ($matches | first | get id))
        if $slim == null {
            $reasons = ($reasons | append "process-count")
            continue
        }
        $seen = $seen + 1
        if $slim.status != "running" {
            $reasons = ($reasons | append "not-running")
            $healthy = false
        }
        if $slim.health != "healthy" {
            $reasons = ($reasons | append "unhealthy")
            $healthy = false
        }
        $reasons = ($reasons | append (restart-count-reason $slim.restarts))
        if $slim.restarts > $restarts {
            $restarts = $slim.restarts
        }
        if $slim.hostname != $svc {
            $reasons = ($reasons | append "hostname-mismatch")
            $hostname_ok = false
        }
        let got = (normalize-image-id $slim.image_id)
        let want = (normalize-image-id $image_id)
        if ($want | is-empty) or ($got != $want) {
            $reasons = ($reasons | append "image-mismatch")
        }
        if ($slim.ip | is-empty) {
            $reasons = ($reasons | append "missing-ip")
        } else {
            $ips = ($ips | append $slim.ip)
        }
    }
    if $seen != $processes {
        $reasons = ($reasons | append "process-count")
    }
    if ($ips | length) != ($ips | uniq | length) {
        $reasons = ($reasons | append "duplicate-ip")
    }
    {
        reasons: (order-reasons $reasons),
        ips: $ips,
        restarts: $restarts,
        hostname_ok: $hostname_ok,
        healthy: $healthy,
        image_id: $image_id,
    }
}

def fetch-monitor [ctx: record, files: list<string>, service: string, path: string] {
    let tail = (compose-tail $ctx $files)
    if $tail == null {
        return null
    }
    let url = $"http://127.0.0.1:8222($path)"
    let argv = (
        ["docker" "compose"]
        | append $tail
        | append ["exec" "-T" $service "wget" "-T" "3" "-qO-" $url]
    )
    let run = (run-capped $argv)
    let body = ($run.stdout | str trim)
    if ($body | is-empty) {
        return null
    }
    let parsed = (try { $body | from json } catch { null })
    if (is-record $parsed) { $parsed } else { null }
}

def healthz-reasons [body: any] {
    if not (is-record $body) {
        return ["monitor-unavailable"]
    }
    let status = ($body.status? | default "" | into string)
    if $status == "ok" {
        []
    } else if $status == "unavailable" {
        ["js-off"]
    } else {
        ["broker-unhealthy"]
    }
}

def find-ps [ps_rows: list, service: string] {
    let matches = ($ps_rows | where {|row| $row.service == $service})
    if ($matches | length) != 1 {
        return null
    }
    $matches | first
}

def identity-party [party: record] {
    {
        role: $party.role,
        processes: $party.processes,
        connections: $party.connections,
        bucket: $party.bucket,
        ttl_seconds: $party.ttl_seconds,
        hostname_ok: $party.hostname_ok,
        image_id: $party.image_id,
    }
}

def identity-of [parties: list, bindings: list] {
    {
        roles: ($parties | each {|party| $party.role} | sort),
        bindings: ($bindings | sort-by role | each {|row|
            {role: $row.role, ips: ($row.ips | sort)}
        }),
        parties: ($parties | sort-by role | each {|party| identity-party $party}),
    }
}

def collect-party [
    ctx: record,
    files: list<string>,
    role: string,
    spec: record,
    reason_order: list<string>,
    check_state: closure,
    watcher_count: closure,
] {
    let services = (revad-services $role $spec.revad_modes)
    if ($services | length) != $spec.processes {
        return {reasons: ["process-count"], party: null, ips: []}
    }
    let broker = (broker-service $role)
    let ps_rows = (compose-ps $ctx $files)
    if $ps_rows == null {
        return {reasons: ["compose-query"], party: null, ips: []}
    }
    let wanted = ($services | append $broker)
    let ids = (
        $ps_rows
        | where {|row| $row.service in $wanted}
        | each {|row| $row.id}
    )
    let inspected = (inspect-ids $ids)
    if $inspected == null {
        return {reasons: ["compose-query"], party: null, ips: []}
    }
    let image_ref = (intended-image-ref $ctx $files $services)
    let image_id = (resolved-image-id $image_ref)
    let revad = (judge-revad $services $ps_rows $inspected $image_id $spec.processes)
    mut reasons = $revad.reasons

    let broker_ps = (find-ps $ps_rows $broker)
    let broker_slim = if $broker_ps == null {
        null
    } else {
        find-slim $inspected $broker_ps.id
    }
    if ($broker_slim == null) or ($broker_slim.status != "running") or ($broker_slim.health != "healthy") {
        $reasons = ($reasons | append "broker-unhealthy")
    } else {
        $reasons = ($reasons | append (restart-count-reason $broker_slim.restarts))
        if $broker_slim.hostname != $broker {
            $reasons = ($reasons | append "hostname-mismatch")
        }
    }

    mut watchers = 0
    if ($broker_slim != null) and ($broker_slim.status == "running") {
        let healthz = (fetch-monitor $ctx $files $broker $spec.healthz_path)
        let connz = (fetch-monitor $ctx $files $broker $spec.connz_path)
        let jsz = (fetch-monitor $ctx $files $broker $spec.jsz_path)
        $reasons = ($reasons | append (healthz-reasons $healthz))
        if ($connz == null) or ($jsz == null) {
            $reasons = ($reasons | append "monitor-unavailable")
        } else if ($revad.ips | length) == $spec.processes {
            let state = (do $check_state $connz $jsz $revad.ips $spec.bucket)
            if not $state.ok {
                $reasons = ($reasons | append $state.reasons)
            }
            $watchers = (do $watcher_count $jsz $spec.bucket)
        }
    }

    let ordered = (order-reasons $reasons --order $reason_order)
    if not ($ordered | is-empty) {
        return {reasons: $ordered, party: null, ips: []}
    }
    {
        reasons: [],
        party: {
            role: $role,
            processes: $spec.processes,
            connections: $spec.processes,
            watchers: $watchers,
            bucket: $spec.bucket,
            ttl_seconds: $spec.ttl_seconds,
            hostname_ok: $revad.hostname_ok,
            image_id: $revad.image_id,
            restarts: $revad.restarts,
            healthy: $revad.healthy,
        },
        ips: ($revad.ips | sort),
    }
}

export def collect-cernbox-sample [
    ctx: record,
    files: list<string>,
    roles: list<string>,
    spec: record,
    reason_order: list<string>,
    check_state: closure,
    watcher_count: closure,
] {
    mut reasons = []
    mut parties = []
    mut bindings = []
    for role in $roles {
        let one = (try {
            (collect-party $ctx $files $role $spec $reason_order
                $check_state $watcher_count)
        } catch {
            {reasons: ["readiness-check"], party: null, ips: []}
        })
        $reasons = ($reasons | append (prefix-reasons $role $one.reasons --order $reason_order))
        if $one.party != null {
            $parties = ($parties | append $one.party)
            $bindings = ($bindings | append {role: $role, ips: $one.ips})
        }
    }
    if ($reasons | is-empty) {
        {
            ok: true,
            reasons: [],
            identity: (identity-of $parties $bindings),
            parties: $parties,
        }
    } else {
        {
            ok: false,
            reasons: ($reasons | uniq),
            identity: {},
            parties: [],
        }
    }
}
