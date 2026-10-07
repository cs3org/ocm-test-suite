# CERNBox Reva service-registry readiness.
# Polls compose and the in-broker NATS monitor, then writes a safe receipt.
# Failure text is fixed reason codes only: no monitor bodies, env, or addresses.

use ../time/utc.nu [utc-now]

const REVAD_MODES = [
    "gateway"
    "dataprovider-localhome"
    "dataprovider-ocm"
    "dataprovider-sciencemesh"
    "authprovider-oidc"
    "authprovider-machine"
    "authprovider-ocmshares"
    "authprovider-ocmsharecode"
    "authprovider-ocmexchangedtoken"
    "authprovider-publicshares"
    "shareproviders"
    "groupuserproviders"
]

const REGISTRY_BUCKET = "reva_registry"
const REGISTRY_CONN = "reva-registry"
const REGISTRY_TTL_NS = 30000000000
const REGISTRY_TTL_SECONDS = 30
const EXPECTED_PROCESSES = 12

const HEALTHZ_PATH = "/healthz?js-enabled-only=true"
const CONNZ_PATH = "/connz?limit=64"
const JSZ_PATH = "/jsz?accounts=true&streams=true&config=true"

const REASON_ORDER = [
    "compose-query"
    "process-count"
    "not-running"
    "unhealthy"
    "restarts"
    "hostname-mismatch"
    "image-mismatch"
    "missing-ip"
    "duplicate-ip"
    "broker-unhealthy"
    "js-off"
    "monitor-unavailable"
    "monitor-truncated"
    "wrong-bucket"
    "ttl-mismatch"
    "zero-messages"
    "watcher-count"
    "missing-connection"
    "foreign-connection"
    "samples-disagree"
    "timeout"
    "receipt-write"
    "readiness-check"
]

def is-list [value: any] {
    let kind = ($value | describe)
    # A list of records describes as table, which is still a list.
    ($kind | str starts-with "list") or ($kind | str starts-with "table")
}

def is-record [value: any] {
    ($value | describe | str starts-with "record")
}

def as-int [value: any] {
    if $value == null {
        return null
    }
    if (($value | describe) == "int") {
        return $value
    }
    try { $value | into int } catch { null }
}

def order-reasons [reasons: list<string>] {
    let uniq = ($reasons | uniq)
    let known = ($REASON_ORDER | where {|code| $code in $uniq})
    let extra = ($uniq | where {|code| not ($code in $REASON_ORDER)})
    $known | append $extra
}

def safe-reason [code: string] {
    if $code in $REASON_ORDER {
        return $code
    }
    let parts = ($code | split row ":")
    if ($parts | length) == 2 {
        let role = ($parts | first)
        let tail = ($parts | last)
        let role_ok = (($role == "sender") or ($role == "receiver"))
        if $role_ok and ($tail in $REASON_ORDER) {
            return $code
        }
    }
    "readiness-check"
}

def fail-readiness [reasons: list<string>] {
    let codes = if ($reasons | is-empty) {
        ["timeout"]
    } else {
        $reasons | each {|code| safe-reason $code} | uniq
    }
    let joined = ($codes | str join ", ")
    error make {msg: $"Reva service registry readiness failed: ($joined)"}
}

def prefix-reasons [role: string, reasons: list<string>] {
    let ordered = (order-reasons $reasons)
    $ordered | each {|code| $"($role):($code)"}
}

# RestartCount above zero is its own fixed reason. The pure monitor check
# does not see container restarts; the compose sample does.
def restart-count-reason [count: int] {
    if $count > 0 { ["restarts"] } else { [] }
}

def platform-name [value: any] {
    if $value == null {
        return ""
    }
    $value | into string | str trim | str lowercase
}

# Sender when that platform is cernbox. Receiver only for a two-party cernbox receiver.
export def registry-parties [cell: record] {
    let sender = (platform-name ($cell.sender_platform? | default ""))
    let receiver = (platform-name ($cell.receiver_platform? | default ""))
    let two = ($cell.is_two_party? | default false)
    mut roles = []
    if $sender == "cernbox" {
        $roles = ($roles | append "sender")
    }
    if $two and ($receiver == "cernbox") {
        $roles = ($roles | append "receiver")
    }
    $roles
}

def revad-services [role: string] {
    $REVAD_MODES | each {|mode| $"($role)-revad-($mode)"}
}

def broker-service [role: string] {
    $"($role)-revad-registry"
}

def conn-ip [raw: any] {
    let text = (if $raw == null { "" } else { $raw | into string | str trim })
    if ($text =~ '^\d+\.\d+\.\d+\.\d+:\d+$') {
        $text | split row ":" | first
    } else {
        $text
    }
}

def kv-stream-rows [jsz: record] {
    let accounts = ($jsz.account_details? | default [])
    if not (is-list $accounts) {
        return []
    }
    $accounts | each {|acct|
        if not (is-record $acct) {
            []
        } else {
            let details = ($acct.stream_detail? | default [])
            if (is-list $details) {
                $details
            } else if (is-record $details) {
                [$details]
            } else {
                []
            }
        }
    } | flatten
}

def stream-name [stream: record] {
    let top = ($stream.name? | default "")
    if not (($top | into string) | is-empty) {
        $top | into string
    } else {
        let nested = ($stream.config?.name? | default "")
        $nested | into string
    }
}

def matching-kv [jsz: record, bucket: string] {
    let want = $"KV_($bucket)"
    let found = (kv-stream-rows $jsz | where {|stream|
        (is-record $stream) and ((stream-name $stream) == $want)
    })
    if ($found | length) != 1 {
        return null
    }
    $found | first
}

def kv-consumer-count [jsz: record, bucket: string] {
    let stream = (matching-kv $jsz $bucket)
    if $stream == null {
        return 0
    }
    let count = (as-int ($stream.state?.consumer_count? | default null))
    if $count == null { 0 } else { $count }
}

# Pure check of one party's broker monitor records.
# ok is false when any fixed reason applies. Reasons never include raw monitor text.
export def registry-readiness-state [
    connz: record,
    jsz: record,
    expected_ips: list<string>,
    bucket: string,
] {
    mut reasons = []

    let connections = ($connz.connections? | default null)
    if ($connz.error? | default null) != null or (not (is-list $connections)) {
        $reasons = ($reasons | append "broker-unhealthy")
    }

    let disabled = ($jsz.disabled? | default false)
    if $disabled or (($jsz.error? | default null) != null) {
        $reasons = ($reasons | append "js-off")
    }

    let stream = (matching-kv $jsz $bucket)
    if $stream == null {
        $reasons = ($reasons | append "wrong-bucket")
    } else {
        let age = (as-int ($stream.config?.max_age? | default null))
        if $age != $REGISTRY_TTL_NS {
            $reasons = ($reasons | append "ttl-mismatch")
        }
        let messages = (as-int ($stream.state?.messages? | default null))
        if ($messages == null) or ($messages <= 0) {
            $reasons = ($reasons | append "zero-messages")
        }
        let watchers = (as-int ($stream.state?.consumer_count? | default null))
        if ($watchers == null) or ($watchers < $EXPECTED_PROCESSES) {
            $reasons = ($reasons | append "watcher-count")
        }
    }

    if (is-list $connections) {
        let total = (as-int ($connz.total? | default null))
        if ($total != null) and ($total > ($connections | length)) {
            $reasons = ($reasons | append "monitor-truncated")
        }
        let named = ($connections | where {|row|
            (is-record $row) and (($row.name? | default "") == $REGISTRY_CONN)
        })
        let seen = ($named | each {|row| conn-ip ($row.ip? | default "")})
        if ($expected_ips | length) != ($expected_ips | uniq | length) {
            $reasons = ($reasons | append "duplicate-ip")
        }
        let missing = ($expected_ips | any {|ip|
            ($seen | where {|item| $item == $ip} | length) == 0
        })
        let duplicated = ($expected_ips | any {|ip|
            ($seen | where {|item| $item == $ip} | length) > 1
        })
        if $missing {
            $reasons = ($reasons | append "missing-connection")
        }
        if $duplicated {
            $reasons = ($reasons | append "duplicate-ip")
        }
        let foreign = ($seen | any {|ip| not ($ip in $expected_ips)})
        if $foreign {
            $reasons = ($reasons | append "foreign-connection")
        }
    }

    let ordered = (order-reasons $reasons)
    {ok: ($ordered | is-empty), reasons: $ordered}
}

def run-capped-job [bin: string, rest: list<string>] {
    let out_path = (^mktemp | str trim)
    let id = (job spawn {
        let result = (try {
            ^($bin) ...$rest | complete
        } catch {
            {exit_code: 127, stdout: ""}
        })
        {exit_code: $result.exit_code, stdout: $result.stdout}
        | to json
        | save --force $out_path
    })
    let deadline = ((date now) + 5sec)
    loop {
        let alive = (not (job list | where {|row| $row.id == $id} | is-empty))
        if not $alive {
            break
        }
        if (date now) >= $deadline {
            try { job kill $id } catch {}
            try { rm -f $out_path } catch {}
            return {exit_code: 124, stdout: ""}
        }
        sleep 100ms
    }
    let raw = (try { open --raw $out_path } catch { "" })
    try { rm -f $out_path } catch {}
    let parsed = (try { $raw | from json } catch { null })
    if not (is-record $parsed) {
        return {exit_code: 1, stdout: ""}
    }
    {
        exit_code: (as-int ($parsed.exit_code? | default 1) | default 1),
        stdout: ($parsed.stdout? | default ""),
    }
}

# Cap one external command at 5 seconds. Stderr is dropped so it cannot leak.
def run-capped [argv: list<string>] {
    if ($argv | is-empty) {
        return {exit_code: 127, stdout: ""}
    }
    let bin = ($argv | first)
    let rest = ($argv | skip 1)
    if not (which timeout | is-empty) {
        let timed = (try {
            ^timeout --signal=KILL 5s $bin ...$rest | complete
        } catch {
            {exit_code: 127, stdout: ""}
        })
        if ($timed.exit_code == 124) or ($timed.exit_code == 137) {
            return {exit_code: 124, stdout: ""}
        }
        return {exit_code: $timed.exit_code, stdout: $timed.stdout}
    }
    run-capped-job $bin $rest
}

def compose-tail [ctx: record, files: list<string>] {
    let project = ($ctx.stack_id? | default "" | str trim)
    if ($project | is-empty) or ($files | is-empty) {
        return null
    }
    let env_file = ($ctx.env_file? | default "")
    let env_args = if ($env_file | is-empty) { [] } else { ["--env-file" $env_file] }
    let f_args = ($files | each {|f| ["-f" $f]} | flatten)
    $env_args | append $f_args | append ["-p" $project]
}

def parse-json-rows [text: string] {
    let trimmed = ($text | str trim)
    if ($trimmed | is-empty) {
        return []
    }
    let whole = (try { $trimmed | from json } catch { null })
    if (is-list $whole) {
        return $whole
    }
    if (is-record $whole) {
        return [$whole]
    }
    $trimmed | lines | each {|line|
        let item = ($line | str trim)
        if ($item | is-empty) {
            null
        } else {
            try { $item | from json } catch { null }
        }
    } | where {|row| $row != null}
}

def ps-service [row: record] {
    let from_field = ($row.Service? | default ($row.service? | default ""))
    $from_field | into string
}

def ps-id [row: record] {
    let from_field = ($row.ID? | default ($row.Id? | default ($row.id? | default "")))
    $from_field | into string
}

def compose-ps [ctx: record, files: list<string>] {
    let tail = (compose-tail $ctx $files)
    if $tail == null {
        return null
    }
    let argv = (["docker" "compose"] | append $tail | append ["ps" "-a" "--format" "json"])
    let run = (run-capped $argv)
    if $run.exit_code != 0 {
        return null
    }
    parse-json-rows $run.stdout | each {|row|
        if not (is-record $row) {
            null
        } else {
            {service: (ps-service $row), id: (ps-id $row)}
        }
    } | where {|row| $row != null}
}

def normalize-image-id [raw: string] {
    let text = ($raw | str trim)
    if ($text | str starts-with "sha256:") {
        $text | str substring 7..
    } else {
        $text
    }
}

# Execution network key is the compose project label. Compose publishes
# ocm-net under that name. Older stacks used ocm-net or a *_ocm-net key.
def container-ip [insp: record] {
    let nets = ($insp.NetworkSettings?.Networks? | default null)
    if not (is-record $nets) {
        return ""
    }
    let rows = ($nets | transpose name net)
    let labels = ($insp.Config?.Labels? | default null)
    let project = if not (is-record $labels) {
        ""
    } else {
        let raw = ($labels | get --optional "com.docker.compose.project" | default "")
        if $raw == null {
            ""
        } else {
            $raw | into string | str trim
        }
    }
    let by_project = if ($project | is-empty) {
        []
    } else {
        $rows | where {|row| $row.name == $project}
    }
    let chosen = if not ($by_project | is-empty) {
        $by_project
    } else {
        $rows | where {|row|
            (($row.name == "ocm-net") or ($row.name | str ends-with "_ocm-net"))
        }
    }
    if ($chosen | is-empty) {
        return ""
    }
    let net = ($chosen | first | get net)
    if not (is-record $net) {
        return ""
    }
    let raw = ($net | get --optional IPAddress | default "")
    if $raw == null {
        return ""
    }
    $raw | into string | str trim
}

def slim-inspect [insp: record] {
    let labels = ($insp.Config?.Labels? | default null)
    let service = if (is-record $labels) {
        $labels | get --optional "com.docker.compose.service" | default ""
    } else {
        ""
    }
    let restart_top = (as-int ($insp.RestartCount? | default null))
    let restart_state = (as-int ($insp.State?.RestartCount? | default null))
    let restarts = if $restart_top != null {
        $restart_top
    } else if $restart_state != null {
        $restart_state
    } else {
        0
    }
    {
        id: ($insp.Id? | default "" | into string),
        service: ($service | into string),
        status: ($insp.State?.Status? | default "" | into string),
        health: ($insp.State?.Health?.Status? | default "" | into string),
        restarts: $restarts,
        hostname: ($insp.Config?.Hostname? | default "" | into string),
        image_id: ($insp.Image? | default "" | into string),
        ip: (container-ip $insp),
    }
}

def inspect-ids [ids: list<string>] {
    let wanted = ($ids | where {|id| not ($id | is-empty)})
    if ($wanted | is-empty) {
        return []
    }
    let argv = (["docker" "inspect"] | append $wanted)
    let run = (run-capped $argv)
    if $run.exit_code != 0 {
        return null
    }
    let rows = (parse-json-rows $run.stdout)
    $rows | each {|row|
        if (is-record $row) { slim-inspect $row } else { null }
    } | where {|row| $row != null}
}

def same-container-id [left: string, right: string] {
    if ($left | is-empty) or ($right | is-empty) {
        return false
    }
    let a = ($left | str replace --regex '^sha256:' '')
    let b = ($right | str replace --regex '^sha256:' '')
    if $a == $b {
        return true
    }
    let a_len = ($a | str length)
    let b_len = ($b | str length)
    let short = if $a_len <= $b_len { $a } else { $b }
    let long = if $a_len <= $b_len { $b } else { $a }
    if ($short | str length) < 12 {
        return false
    }
    if not ($short =~ '^[0-9a-fA-F]+$') {
        return false
    }
    $long | str starts-with $short
}

def find-slim [rows: list, id: string] {
    let hit = ($rows | where {|row| same-container-id $row.id $id})
    if ($hit | is-empty) { null } else { $hit | first }
}

def intended-image-ref [ctx: record, files: list<string>, services: list<string>] {
    let tail = (compose-tail $ctx $files)
    if $tail == null {
        return ""
    }
    let argv = (["docker" "compose"] | append $tail | append ["config" "--format" "json"])
    let run = (run-capped $argv)
    if $run.exit_code != 0 {
        return ""
    }
    let cfg = (try { $run.stdout | from json } catch { null })
    if not (is-record $cfg) {
        return ""
    }
    let specs = ($cfg.services? | default null)
    if not (is-record $specs) {
        return ""
    }
    let images = ($services | each {|name|
        let spec = ($specs | get --optional $name)
        if not (is-record $spec) {
            ""
        } else {
            let image = ($spec.image? | default ($spec.Image? | default ""))
            $image | into string | str trim
        }
    })
    if ($images | any {|image| $image | is-empty}) {
        return ""
    }
    let uniq = ($images | uniq)
    if ($uniq | length) != 1 {
        return ""
    }
    $uniq | first
}

def resolved-image-id [image_ref: string] {
    if ($image_ref | is-empty) {
        return ""
    }
    let argv = ["docker" "image" "inspect" "--format" "{{.Id}}" $image_ref]
    let run = (run-capped $argv)
    if $run.exit_code != 0 {
        return ""
    }
    $run.stdout | str trim
}

def judge-revad [services: list<string>, ps_rows: list, inspected: list, image_id: string] {
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
    if $seen != $EXPECTED_PROCESSES {
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

def collect-party [ctx: record, files: list<string>, role: string] {
    let services = (revad-services $role)
    if ($services | length) != $EXPECTED_PROCESSES {
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
    let revad = (judge-revad $services $ps_rows $inspected $image_id)
    mut reasons = $revad.reasons

    let broker_ps = (find-ps $ps_rows $broker)
    let broker_slim = if $broker_ps == null { null } else { find-slim $inspected $broker_ps.id }
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
        let healthz = (fetch-monitor $ctx $files $broker $HEALTHZ_PATH)
        let connz = (fetch-monitor $ctx $files $broker $CONNZ_PATH)
        let jsz = (fetch-monitor $ctx $files $broker $JSZ_PATH)
        $reasons = ($reasons | append (healthz-reasons $healthz))
        if ($connz == null) or ($jsz == null) {
            $reasons = ($reasons | append "monitor-unavailable")
        } else if ($revad.ips | length) == $EXPECTED_PROCESSES {
            let state = (registry-readiness-state $connz $jsz $revad.ips $REGISTRY_BUCKET)
            if not $state.ok {
                $reasons = ($reasons | append $state.reasons)
            }
            $watchers = (kv-consumer-count $jsz $REGISTRY_BUCKET)
        }
    }

    let ordered = (order-reasons $reasons)
    if not ($ordered | is-empty) {
        return {reasons: $ordered, party: null, ips: []}
    }
    {
        reasons: [],
        party: {
            role: $role,
            processes: $EXPECTED_PROCESSES,
            connections: $EXPECTED_PROCESSES,
            watchers: $watchers,
            bucket: $REGISTRY_BUCKET,
            ttl_seconds: $REGISTRY_TTL_SECONDS,
            hostname_ok: $revad.hostname_ok,
            image_id: $revad.image_id,
            restarts: $revad.restarts,
            healthy: $revad.healthy,
        },
        ips: ($revad.ips | sort),
    }
}

def collect-sample [ctx: record, files: list<string>, roles: list<string>] {
    mut reasons = []
    mut parties = []
    mut bindings = []
    for role in $roles {
        let one = (try {
            collect-party $ctx $files $role
        } catch {
            {reasons: ["readiness-check"], party: null, ips: []}
        })
        $reasons = ($reasons | append (prefix-reasons $role $one.reasons))
        if $one.party != null {
            $parties = ($parties | append $one.party)
            $bindings = ($bindings | append {role: $role, ips: $one.ips})
        }
    }
    if ($reasons | is-empty) {
        {ok: true, reasons: [], parties: $parties, bindings: $bindings}
    } else {
        {
            ok: false,
            reasons: ($reasons | uniq),
            parties: [],
            bindings: [],
        }
    }
}

def sample-fingerprint [sample: record] {
    {
        parties: $sample.parties,
        bindings: $sample.bindings,
    } | to json
}

def receipt-path [ctx: record] {
    $ctx.artifacts_base | path join "cypress/downloads/local-e2e/reva-registry-readiness.json"
}

def merge-readiness-receipt [ctx: record, phase: string, phase_body: record] {
    let base_dir = ($ctx.artifacts_base? | default "")
    if ($base_dir | is-empty) {
        fail-readiness ["receipt-write"]
    }
    let path = (receipt-path $ctx)
    let existing = if ($path | path exists) {
        try { open $path } catch { null }
    } else {
        null
    }
    let from_ctx = ($ctx.execution_id? | default "")
    let keep_existing = (is-record $existing)
    let execution_id = if $keep_existing and (not (($existing.execution_id? | default "") | is-empty)) {
        $existing.execution_id
    } else {
        $from_ctx
    }
    let old_phases = if $keep_existing and (is-record ($existing.phases? | default null)) {
        $existing.phases
    } else {
        {}
    }
    let phases = ($old_phases | upsert $phase $phase_body)
    let out = if $keep_existing {
        $existing
        | upsert schema_version 1
        | upsert execution_id $execution_id
        | upsert phases $phases
    } else {
        {
            schema_version: 1,
            execution_id: $execution_id,
            phases: $phases,
        }
    }
    let wrote = (try {
        mkdir ($path | path dirname)
        $out | to json --indent 2 | save --force $path
        true
    } catch {
        false
    })
    if not $wrote {
        fail-readiness ["receipt-write"]
    }
    $out
}

def commit-receipt [ctx: record, phase: string, parties: list] {
    merge-readiness-receipt $ctx $phase {
        status: "passed",
        captured_at: (utc-now),
        parties: $parties,
    }
}

def skipped-receipt [ctx: record] {
    {
        schema_version: 1,
        execution_id: ($ctx.execution_id? | default ""),
        phases: {},
    }
}

# No-op when the cell has no CERNBox party. Otherwise require two matching
# samples 5 seconds apart before writing the phase receipt.
export def wait-reva-registries [
    ctx: record,
    files: list<string>,
    --timeout: duration = 120sec,
    --phase: string = "before-cypress",
] {
    let roles = (registry-parties ($ctx.cell? | default {}))
    if ($roles | is-empty) {
        return (skipped-receipt $ctx)
    }
    if (compose-tail $ctx $files) == null {
        fail-readiness ["compose-query"]
    }

    let deadline = ((date now) + $timeout)
    mut have_first = false
    mut first = {ok: false, reasons: [], parties: [], bindings: []}
    mut first_at = (date now)
    mut last_reasons = ["timeout"]

    loop {
        if (date now) >= $deadline {
            break
        }
        let sample = (collect-sample $ctx $files $roles)
        if $sample.ok {
            let now = (date now)
            if $have_first {
                let same = ((sample-fingerprint $sample) == (sample-fingerprint $first))
                let age = ($now - $first_at)
                if $same and ($age >= 5sec) {
                    return (commit-receipt $ctx $phase $sample.parties)
                } else if $same {
                    $last_reasons = ["timeout"]
                } else {
                    $first = $sample
                    $first_at = $now
                    $last_reasons = ["samples-disagree"]
                }
            } else {
                $first = $sample
                $first_at = $now
                $have_first = true
                $last_reasons = ["timeout"]
            }
        } else {
            $have_first = false
            $last_reasons = $sample.reasons
        }
        let remain = ($deadline - (date now))
        if $remain <= 0sec {
            break
        }
        let pause = if $remain > 2sec { 2sec } else { $remain }
        sleep $pause
    }
    fail-readiness $last_reasons
}
