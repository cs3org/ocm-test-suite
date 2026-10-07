# CERNBox Reva service-registry provider.
# The image is the source of truth for what reva does. This gate asserts
# the suite constants. Drift surfaces as ttl-mismatch, watcher-count, or
# wrong-bucket. Do not edit the constants to match a drifted image.

use ./records.nu [is-record]
use ./readiness-reasons.nu [order-reasons]
use ./reva-registry-sample.nu [collect-cernbox-sample]

const CERNBOX_ROLE_NAMES = ["sender" "receiver"]

# Codes that are not in the shared core. The first four used to live in
# that shared list; they stay here so CERNBox evidence text does not change.
const CERNBOX_REASON_CODES = [
    "compose-query"
    "broker-unhealthy"
    "js-off"
    "monitor-truncated"
    "wrong-bucket"
    "ttl-mismatch"
    "zero-messages"
    "watcher-count"
    "missing-connection"
    "foreign-connection"
    "samples-disagree"
]

# Observable CERNBox sort sequence, shared slots included.
const CERNBOX_REASON_ORDER = [
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
    "timeout"
    "evidence-write"
    "readiness-check"
    "wrong-bucket"
    "ttl-mismatch"
    "zero-messages"
    "watcher-count"
    "missing-connection"
    "foreign-connection"
    "samples-disagree"
]

const reva_registry_ttl_seconds = 30

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

export def reva-registry-constants [] {
    {
        processes: 12,
        bucket: "reva_registry",
        conn: "reva-registry",
        ttl_seconds: $reva_registry_ttl_seconds,
        ttl_ns: ($reva_registry_ttl_seconds * 1000000000),
        heartbeat_interval: "5s",
        degraded_after: "15s",
        offline_after: "30s",
        reap_after: "5m",
        healthz_path: "/healthz?js-enabled-only=true",
        connz_path: "/connz?limit=64",
        jsz_path: "/jsz?accounts=true&streams=true&config=true",
        revad_modes: $REVAD_MODES,
    }
}

def is-list [value: any] {
    let kind = ($value | describe)
    ($kind | str starts-with "list") or ($kind | str starts-with "table")
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

def platform-name [value: any] {
    if $value == null {
        return ""
    }
    $value | into string | str trim | str lowercase
}

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

def registry-kv-consumer-count [jsz: record, bucket: string] {
    let stream = (matching-kv $jsz $bucket)
    if $stream == null {
        return 0
    }
    let count = (as-int ($stream.state?.consumer_count? | default null))
    if $count == null { 0 } else { $count }
}

export def registry-readiness-state [
    connz: record,
    jsz: record,
    expected_ips: list<string>,
    bucket: string,
] {
    let spec = (reva-registry-constants)
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
        if $age != $spec.ttl_ns {
            $reasons = ($reasons | append "ttl-mismatch")
        }
        let messages = (as-int ($stream.state?.messages? | default null))
        if ($messages == null) or ($messages <= 0) {
            $reasons = ($reasons | append "zero-messages")
        }
        let watchers = (as-int ($stream.state?.consumer_count? | default null))
        if ($watchers == null) or ($watchers < $spec.processes) {
            $reasons = ($reasons | append "watcher-count")
        }
    }

    if (is-list $connections) {
        let total = (as-int ($connz.total? | default null))
        if ($total != null) and ($total > ($connections | length)) {
            $reasons = ($reasons | append "monitor-truncated")
        }
        let named = ($connections | where {|row|
            (is-record $row) and (($row.name? | default "") == $spec.conn)
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

    let ordered = (order-reasons $reasons --order $CERNBOX_REASON_ORDER)
    {ok: ($ordered | is-empty), reasons: $ordered}
}

export def reva-registry-provider [] {
    let spec = (reva-registry-constants)
    {
        name: "cernbox-registry",
        label: "Reva service registry",
        stability_interval: 5sec,
        reason_codes: $CERNBOX_REASON_CODES,
        role_names: $CERNBOX_ROLE_NAMES,
        reason_order: $CERNBOX_REASON_ORDER,
        parties: {|cell| registry-parties $cell },
        sample: {|ctx, files, roles|
            (collect-cernbox-sample $ctx $files $roles $spec $CERNBOX_REASON_ORDER
                {|connz, jsz, ips, bucket|
                    registry-readiness-state $connz $jsz $ips $bucket
                }
                {|jsz, bucket| registry-kv-consumer-count $jsz $bucket })
        },
    }
}
