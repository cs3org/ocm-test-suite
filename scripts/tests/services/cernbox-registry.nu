# CERNBox Reva registry readiness tests.
# Pure checker fixtures, fake-docker poller bounds, receipt shape, and
# infra-fail exit-code clamping. No daemon and no docker compose.
# Run: nu scripts/tests/services/cernbox-registry.nu

const SUITE_PATH = path self

use ../../lib/services/reva-registry.nu [
    registry-parties
    registry-readiness-state
    wait-reva-registries
]
use ../../lib/services/infra-fail.nu [with-infra-fail-cleanup]
use ../../lib/time/utc.nu [utc-now]
use ../../lib/tests/assert.nu *
use ../../lib/tests/fixtures.nu [with-tmp-dir]
use ../../lib/tests/runner.nu [run-suite]

const IMAGE_ID = "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
const LEAK_TOKEN = "fixture-token-9f3c1a"
const LEAK_ADDR = "nats://10.9.8.7:4222"
const EXEC_PROJECT = "ocmts--cell-login-cernbox-v11--20261007t033844-c5e486b4"
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

def path-prepend [prefix: string] {
    [$prefix] | append $env.PATH
}

def two-digit [n: int] {
    if $n < 10 { $"0($n)" } else { $"($n)" }
}

def container-id [n: int] {
    let prefix = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
    $"sha256:($prefix)(two-digit $n)"
}

def revad-ip [n: int] {
    $"10.51.0.($n)"
}

# Default network key equals the compose project label. Pass net_name to
# model a legacy *_ocm-net key or a network that is not the execution net.
def inspect-row [
    service: string,
    id: string,
    ip: string,
    restarts: int,
    net_name: string = "",
    project: string = "",
] {
    let resolved_project = if ($project | is-empty) { $EXEC_PROJECT } else { $project }
    let resolved_net = if ($net_name | is-empty) { $resolved_project } else { $net_name }
    let networks = ({} | insert $resolved_net {IPAddress: $ip})
    {
        Id: $id,
        RestartCount: $restarts,
        Image: $IMAGE_ID,
        Config: {
            Hostname: $service,
            Labels: {
                "com.docker.compose.service": $service,
                "com.docker.compose.project": $resolved_project,
            },
        },
        State: {
            Status: "running",
            Health: {Status: "healthy"},
            RestartCount: $restarts,
        },
        NetworkSettings: {
            Networks: $networks,
        },
    }
}

def party-fixtures [
    role: string,
    gateway_restarts: int,
    net_name: string = "",
    project: string = "",
] {
    let services = ($REVAD_MODES | each {|mode| $"($role)-revad-($mode)"})
    let rows = ($services | enumerate | each {|e|
        let n = $e.index + 1
        let restarts = if ($e.item | str ends-with "-gateway") { $gateway_restarts } else { 0 }
        {
            service: $e.item,
            id: (container-id $n),
            ip: (revad-ip $n),
            restarts: $restarts,
        }
    })
    let broker = $"($role)-revad-registry"
    let with_broker = ($rows | append {
        service: $broker,
        id: (container-id 13),
        ip: "10.51.0.20",
        restarts: 0,
    })
    {
        ips: ($rows | get ip),
        ps: ($with_broker | each {|row| {ID: $row.id, Service: $row.service}}),
        inspect: ($with_broker | each {|row|
            inspect-row $row.service $row.id $row.ip $row.restarts $net_name $project
        }),
        config_services: ($services | reduce --fold {} {|name, acc|
            $acc | upsert $name {image: "cernbox-revad:fixture"}
        }),
    }
}

def write-monitor-files [dir: string, ips: list<string>, watchers: int] {
    {status: "ok"} | to json | save --force ($dir | path join "healthz.json")
    {
        total: ($ips | length),
        connections: ($ips | each {|ip| {name: "reva-registry", ip: $"($ip):4222"}}),
    } | to json | save --force ($dir | path join "connz.json")
    {
        disabled: false,
        account_details: [{
            stream_detail: [{
                name: "KV_reva_registry",
                state: {messages: 12, consumer_count: $watchers},
                config: {max_age: 30000000000},
            }],
        }],
    } | to json | save --force ($dir | path join $"jsz-($watchers).json")
}

def write-registry-fixtures [
    dir: string,
    role: string,
    net_name: string = "",
    project: string = "",
] {
    mkdir $dir
    let healthy = (party-fixtures $role 0 $net_name $project)
    let restarted = (party-fixtures $role 2 $net_name $project)
    ($healthy.ps | each {|row| $row | to json --raw} | str join "\n")
        | save --force ($dir | path join "ps.jsonl")
    $healthy.inspect | to json | save --force ($dir | path join "inspect.json")
    $restarted.inspect | to json | save --force ($dir | path join "inspect-restarts.json")
    {services: $healthy.config_services} | to json | save --force ($dir | path join "compose-config.json")
    $IMAGE_ID | save --force ($dir | path join "image-id.txt")
    write-monitor-files $dir $healthy.ips 12
    write-monitor-files $dir $healthy.ips 13
}

def write-fake-docker [bin_dir: string] {
    mkdir $bin_dir
    let script = '#!/bin/sh
log="${FAKE_REG_LOG:-/dev/null}"
fix="${FAKE_REG_DIR:-}"
printf "%s\n" "$*" >> "$log"
case "$*" in
  *network\ ls*)
    exit 0
    ;;
  *network\ inspect*)
    exit 1
    ;;
  *\ config\ --format\ json*)
    cat "$fix/compose-config.json"
    exit 0
    ;;
  *\ config\ --services*)
    printf "%s\n" "sender"
    exit 0
    ;;
  *\ config*)
    printf "%s\n" "name: fake"
    exit 0
    ;;
  *ps\ -a*)
    if [ "${FAKE_REG_PS_FAIL:-}" = "1" ]; then
      printf "%s\n" "${FAKE_REG_STDERR:-}" >&2
      exit 1
    fi
    cat "$fix/ps.jsonl"
    exit 0
    ;;
  *image\ inspect\ --format*)
    cat "$fix/image-id.txt"
    exit 0
    ;;
  *image\ inspect*)
    exit 1
    ;;
  *inspect*)
    if [ "${FAKE_REG_INSPECT_RESTARTS:-}" = "1" ]; then
      cat "$fix/inspect-restarts.json"
    else
      cat "$fix/inspect.json"
    fi
    exit 0
    ;;
  *exec*)
    if [ -n "${FAKE_REG_STDERR:-}" ]; then
      printf "%s\n" "${FAKE_REG_STDERR:-}" >&2
    fi
    case "$*" in
      *healthz*)
        cat "$fix/healthz.json"
        exit 0
        ;;
      *connz*)
        cat "$fix/connz.json"
        exit 0
        ;;
      *jsz*)
        if [ -n "${FAKE_REG_JSZ_COUNTER:-}" ]; then
          n=$(cat "$FAKE_REG_JSZ_COUNTER" 2>/dev/null || echo 0)
          n=$((n + 1))
          printf "%s" "$n" > "$FAKE_REG_JSZ_COUNTER"
          if [ $((n % 2)) -eq 0 ]; then
            cat "$fix/jsz-13.json"
          else
            cat "$fix/jsz-12.json"
          fi
          exit 0
        fi
        cat "$fix/jsz-12.json"
        exit 0
        ;;
      *)
        exit 1
        ;;
    esac
    ;;
  *logs*)
    printf "%s\n" "log-line"
    exit 0
    ;;
  *down*)
    exit 0
    ;;
  *)
    printf "%s\n" "fake-docker unhandled: $*" >&2
    exit 99
    ;;
esac
'
    $script | save --force ($bin_dir | path join "docker")
    ^chmod +x ($bin_dir | path join "docker")
}

def fake-env [
    tmp: string,
    extra: record,
    net_name: string = "",
    project: string = "",
] {
    let bin_dir = ($tmp | path join "bin")
    let fix_dir = ($tmp | path join "fix")
    write-fake-docker $bin_dir
    write-registry-fixtures $fix_dir "sender" $net_name $project
    let log = ($tmp | path join "docker.log")
    "" | save --force $log
    {
        PATH: (path-prepend $bin_dir),
        FAKE_REG_LOG: $log,
        FAKE_REG_DIR: $fix_dir,
    } | merge $extra
}

def registry-ctx [artifacts_base: string, cell: record, execution_id: string] {
    {
        artifacts_base: $artifacts_base,
        execution_id: $execution_id,
        stack_id: $"ocmts-reg-($execution_id)",
        env_file: "",
        cell: $cell,
    }
}

def cernbox-sender-cell [] {
    {
        sender_platform: "cernbox",
        receiver_platform: "",
        is_two_party: false,
    }
}

def receipt-file [artifacts_base: string] {
    $artifacts_base | path join "cypress/downloads/local-e2e/reva-registry-readiness.json"
}

def read-log [tmp: string] {
    let log = ($tmp | path join "docker.log")
    if not ($log | path exists) { "" } else { open --raw $log }
}

def infra-ctx [artifacts_base: string] {
    {
        artifacts_base: $artifacts_base,
        execution_id: "20260101t120000-aabbccdd",
        cell: {
            cell_id: "login__cernbox-v11",
            artifact_name: "cell-login-cernbox-v11",
            flow_id: "login",
            pair: "cernbox-v11",
        },
        started_at: (utc-now),
        stack_id: "ocmts-test-stack",
        images: null,
        suite_id: "",
        suite_kind: "single",
    }
}

def caught-msg [block: closure] {
    try { do $block; "" } catch {|e| $e.msg}
}

def party-columns [] {
    [
        "bucket" "connections" "healthy" "hostname_ok" "image_id"
        "processes" "restarts" "role" "ttl_seconds" "watchers"
    ]
}

def healthy-connz [ips: list<string>] {
    {
        total: ($ips | length),
        connections: ($ips | each {|ip| {name: "reva-registry", ip: $"($ip):4222"}}),
    }
}

def healthy-jsz [messages: int, watchers: int, max_age: int, bucket: string] {
    {
        disabled: false,
        account_details: [{
            stream_detail: [{
                name: $"KV_($bucket)",
                state: {messages: $messages, consumer_count: $watchers},
                config: {max_age: $max_age},
            }],
        }],
    }
}

def sample-ips [] {
    1..12 | each {|n| $"10.51.0.($n)"}
}

def readiness [connz: record, jsz: record, ips: list<string>] {
    registry-readiness-state $connz $jsz $ips "reva_registry"
}

def test-registry-parties [] {
    test-log "\n[test-registry-parties]"
    let sender = (registry-parties (cernbox-sender-cell))
    let receiver = (registry-parties {
        sender_platform: "nextcloud",
        receiver_platform: "cernbox",
        is_two_party: true,
    })
    let pair = (registry-parties {
        sender_platform: "CERNBox",
        receiver_platform: "cernbox",
        is_two_party: true,
    })
    let one_party_ignores_receiver = (registry-parties {
        sender_platform: "cernbox",
        receiver_platform: "cernbox",
        is_two_party: false,
    })
    let plain = (registry-parties {
        sender_platform: "nextcloud",
        receiver_platform: "ocis",
        is_two_party: true,
    })
    [
        (assert-eq $sender ["sender"] "one-party CERNBox discovers sender only")
        (assert-eq $receiver ["receiver"] "two-party CERNBox receiver discovers receiver only")
        (assert-eq $pair ["sender" "receiver"] "pair discovers sender then receiver")
        (assert-eq $one_party_ignores_receiver ["sender"]
            "one-party ignores a CERNBox receiver platform")
        (assert-eq $plain [] "non-CERNBox pair discovers no registry party")
    ]
}

def test-registry-parties-non-cernbox-no-docker [] {
    test-log "\n[test-registry-parties-non-cernbox-no-docker]"
    with-tmp-dir {|tmp|
        let art = ($tmp | path join "artifacts")
        mkdir $art
        let env_map = (fake-env $tmp {})
        let ctx = (registry-ctx $art {
            sender_platform: "nextcloud",
            receiver_platform: "ocis",
            is_two_party: true,
        } "20260101t000000-aabbccdd")
        let got = (with-env $env_map {
            wait-reva-registries $ctx ["compose.yml"] --phase "platform-ready"
        })
        let log = (read-log $tmp)
        [
            (assert-eq $got.schema_version 1 "skipped receipt keeps schema_version 1")
            (assert-eq $got.execution_id "20260101t000000-aabbccdd"
                "skipped receipt echoes the execution id")
            (assert-eq $got.phases {} "non-CERNBox wait returns an empty phase map")
            (assert-truthy (not ((receipt-file $art) | path exists))
                "non-CERNBox wait does not write a receipt file")
            (assert-eq ($log | str trim) "" "non-CERNBox wait invokes no docker command")
        ]
    }
}

def test-readiness-healthy-and-js-off [] {
    test-log "\n[test-readiness-healthy-and-js-off]"
    let ips = (sample-ips)
    let ok = (readiness (healthy-connz $ips) (healthy-jsz 12 12 30000000000 "reva_registry") $ips)
    let js = (readiness (healthy-connz $ips) ((healthy-jsz 12 12 30000000000 "reva_registry") | upsert disabled true) $ips)
    let boom = (readiness (healthy-connz $ips) ((healthy-jsz 12 12 30000000000 "reva_registry") | upsert error "monitor") $ips)
    [
        (assert-eq $ok.ok true "healthy monitor records are ready")
        (assert-eq $ok.reasons [] "healthy monitor has no reasons")
        (assert-eq $js.ok false "JetStream disabled is not ready")
        (assert-eq $js.reasons ["js-off"] "JetStream disabled reason is js-off")
        (assert-eq $boom.reasons ["js-off"] "monitor error on jsz is js-off")
    ]
}

def test-readiness-bucket-ttl-messages-watchers [] {
    test-log "\n[test-readiness-bucket-ttl-messages-watchers]"
    let ips = (sample-ips)
    let connz = (healthy-connz $ips)
    let bad_bucket = (readiness $connz (healthy-jsz 12 12 30000000000 "other") $ips)
    let ttl = (readiness $connz (healthy-jsz 12 12 1 "reva_registry") $ips)
    let zero = (readiness $connz (healthy-jsz 0 12 30000000000 "reva_registry") $ips)
    let watchers = (readiness $connz (healthy-jsz 12 11 30000000000 "reva_registry") $ips)
    let ordered = (readiness $connz (healthy-jsz 0 11 1 "reva_registry") $ips)
    [
        (assert-eq $bad_bucket.reasons ["wrong-bucket"] "missing KV_reva_registry is wrong-bucket")
        (assert-eq $ttl.reasons ["ttl-mismatch"] "max_age other than 30s is ttl-mismatch")
        (assert-eq $zero.reasons ["zero-messages"] "zero stream messages is zero-messages")
        (assert-eq $watchers.reasons ["watcher-count"] "consumer_count below 12 is watcher-count")
        (assert-eq $ordered.reasons ["ttl-mismatch" "zero-messages" "watcher-count"]
            "bucket reasons stay in fixed order")
    ]
}

def test-readiness-connections [] {
    test-log "\n[test-readiness-connections]"
    let ips = (sample-ips)
    let jsz = (healthy-jsz 12 12 30000000000 "reva_registry")
    let dup_ips = ($ips | append ($ips | first))
    let duplicate = (readiness (healthy-connz $dup_ips | upsert total 13) $jsz $ips)
    let missing = (readiness (healthy-connz ($ips | take 11) | upsert total 11) $jsz $ips)
    let foreign_conn = (healthy-connz ($ips | append "10.9.9.9") | upsert total 13)
    let foreign = (readiness $foreign_conn $jsz $ips)
    let peer = (readiness (healthy-connz ($ips | drop 1 | append "10.8.8.8") | upsert total 12) $jsz $ips)
    let truncated = (readiness (healthy-connz $ips | upsert total 64) $jsz $ips)
    let broker = (readiness {error: "closed"} $jsz $ips)
    [
        (assert-eq $duplicate.reasons ["duplicate-ip"] "a repeated Reva IP is duplicate-ip")
        (assert-eq $missing.reasons ["missing-connection"] "a missing Reva IP is missing-connection")
        (assert-eq $foreign.reasons ["foreign-connection"] "an extra IP is foreign-connection")
        (assert-truthy ("foreign-connection" in $peer.reasons)
            "a peer-party IP is foreign-connection")
        (assert-truthy ("missing-connection" in $peer.reasons)
            "a peer-party IP that replaces a local IP is also missing-connection")
        (assert-eq $truncated.reasons ["monitor-truncated"] "connz total above the page is monitor-truncated")
        (assert-eq $broker.reasons ["broker-unhealthy"] "connz error is broker-unhealthy")
    ]
}

def test-wait-timeout-and-compose-query [] {
    test-log "\n[test-wait-timeout-and-compose-query]"
    with-tmp-dir {|tmp|
        let art = ($tmp | path join "artifacts")
        mkdir $art
        let env_map = (fake-env $tmp {})
        let ctx = (registry-ctx $art (cernbox-sender-cell) "20260101t000000-aabbccdd")
        let timed = (with-env $env_map {
            caught-msg {|| wait-reva-registries $ctx ["compose.yml"] --timeout 0sec --phase "before-cypress" }
        })
        let log_after_timeout = (read-log $tmp)
        let missing = (with-env $env_map {
            caught-msg {||
                wait-reva-registries ($ctx | upsert stack_id "") ["compose.yml"] --timeout 5sec
            }
        })
        [
            (assert-eq $timed "Reva service registry readiness failed: timeout"
                "a zero timeout fails with the fixed timeout reason")
            (assert-eq ($log_after_timeout | str trim) ""
                "a zero timeout returns before any docker command")
            (assert-eq $missing "Reva service registry readiness failed: compose-query"
                "a blank project fails with compose-query")
            (assert-truthy (not ((receipt-file $art) | path exists))
                "a failed wait does not write a receipt")
        ]
    }
}

def test-wait-restarts-and-retries [] {
    test-log "\n[test-wait-restarts-and-retries]"
    with-tmp-dir {|tmp|
        let art = ($tmp | path join "artifacts")
        mkdir $art
        let env_map = (fake-env $tmp {FAKE_REG_INSPECT_RESTARTS: "1"})
        let ctx = (registry-ctx $art (cernbox-sender-cell) "20260101t000000-bbccddee")
        let msg = (with-env $env_map {
            caught-msg {||
                wait-reva-registries $ctx ["compose.yml"] --timeout 5sec --phase "before-cypress"
            }
        })
        let log = (read-log $tmp)
        let ps_calls = ($log | lines | where {|line| $line | str contains "ps -a"} | length)
        [
            (assert-string-contains $msg "sender:restarts"
                "RestartCount above zero fails the poller with restarts")
            (assert-truthy ($ps_calls >= 2)
                "a short timeout still retries compose ps")
            (assert-truthy (not ((receipt-file $art) | path exists))
                "a restart failure writes no receipt")
            (assert-truthy (not ($msg | str contains $LEAK_TOKEN))
                "restart failure text has no fixture token")
        ]
    }
}

def test-wait-samples-disagree [] {
    test-log "\n[test-wait-samples-disagree]"
    with-tmp-dir {|tmp|
        let art = ($tmp | path join "artifacts")
        mkdir $art
        let counter = ($tmp | path join "jsz.count")
        "0" | save --force $counter
        let env_map = (fake-env $tmp {FAKE_REG_JSZ_COUNTER: $counter})
        let ctx = (registry-ctx $art (cernbox-sender-cell) "20260101t000000-ccddeeff")
        let msg = (with-env $env_map {
            caught-msg {||
                wait-reva-registries $ctx ["compose.yml"] --timeout 8sec --phase "before-cypress"
            }
        })
        [
            (assert-eq $msg "Reva service registry readiness failed: samples-disagree"
                "changing watcher counts fail with samples-disagree")
            (assert-truthy (not ((receipt-file $art) | path exists))
                "disagreeing samples write no receipt")
        ]
    }
}

def blank-fixture-ips [tmp: string] {
    let path = ($tmp | path join "fix" "inspect.json")
    let rows = (open $path)
    let updated = ($rows | each {|row|
        let name = ($row.NetworkSettings.Networks | columns | first)
        let nets = ({} | insert $name {IPAddress: "   "})
        $row | upsert NetworkSettings {Networks: $nets}
    })
    $updated | to json | save --force $path
}

def project-net-aligned [tmp: string] {
    let rows = (open ($tmp | path join "fix" "inspect.json"))
    $rows | all {|row|
        let label = ($row.Config.Labels."com.docker.compose.project")
        let keys = ($row.NetworkSettings.Networks | columns)
        ($label == $EXEC_PROJECT) and ($keys == [$EXEC_PROJECT])
    }
}

def test-wait-receipt-phases [] {
    test-log "\n[test-wait-receipt-phases]"
    with-tmp-dir {|tmp|
        let art = ($tmp | path join "artifacts")
        mkdir $art
        let env_map = (fake-env $tmp {})
        let aligned = (project-net-aligned $tmp)
        let exec_id = "20260101t000000-aabbccdd"
        let ctx = (registry-ctx $art (cernbox-sender-cell) $exec_id)
        let other = ($ctx | upsert execution_id "20260101t000000-11223344")
        with-env $env_map {
            wait-reva-registries $ctx ["compose.yml"] --timeout 20sec --phase "before-cypress"
        }
        let first = (open (receipt-file $art))
        let before_at = $first.phases.before-cypress.captured_at
        with-env $env_map {
            wait-reva-registries $other ["compose.yml"] --timeout 20sec --phase "after-cypress"
        }
        let second = (open (receipt-file $art))
        with-env $env_map {
            wait-reva-registries ($other | upsert execution_id "20260101t000000-55667788") ["compose.yml"] --timeout 20sec --phase "before-cypress"
        }
        let third = (open (receipt-file $art))
        let party = ($third.phases.before-cypress.parties | first)
        let text = (open --raw (receipt-file $art))
        [
            (assert-truthy $aligned
                "fixture network key equals the compose project label")
            (assert-eq $second.execution_id $exec_id
                "a later phase keeps the receipt execution id")
            (assert-eq $second.phases.before-cypress.captured_at $before_at
                "appending a phase leaves the earlier phase in place")
            (assert-eq ($second.phases | columns | sort) ["after-cypress" "before-cypress"]
                "receipt phases are the two named gates")
            (assert-eq $third.execution_id $exec_id
                "replacing a phase keeps the original execution id")
            (assert-eq $third.phases.after-cypress $second.phases.after-cypress
                "replacing before-cypress leaves after-cypress unchanged")
            (assert-truthy ($third.phases.before-cypress.captured_at != $before_at)
                "replacing before-cypress writes a new captured_at")
            (assert-eq $third.schema_version 1 "receipt schema_version is 1")
            (assert-eq $party.role "sender" "receipt party role is sender")
            (assert-eq $party.processes 12 "receipt processes is 12")
            (assert-eq $party.connections 12 "receipt connections is 12")
            (assert-eq $party.watchers 12 "receipt watchers is 12")
            (assert-eq $party.bucket "reva_registry" "receipt bucket is reva_registry")
            (assert-eq $party.ttl_seconds 30 "receipt ttl_seconds is 30")
            (assert-eq $party.hostname_ok true "receipt hostname_ok is true")
            (assert-eq $party.image_id $IMAGE_ID "receipt image_id is the resolved id")
            (assert-eq $party.restarts 0 "receipt restarts is 0")
            (assert-eq $party.healthy true "receipt healthy is true")
            (assert-eq ($party | columns | sort) (party-columns)
                "receipt party has only the safe fields")
            (assert-truthy (not ($text | str contains "10.51.0."))
                "receipt omits fixture container addresses")
            (assert-truthy (not ($text | str contains "stream_detail"))
                "receipt omits monitor stream dumps")
            (assert-truthy (not ($text | str contains $LEAK_TOKEN))
                "receipt omits fixture tokens")
        ]
    }
}

def test-wait-safe-docker-errors [] {
    test-log "\n[test-wait-safe-docker-errors]"
    with-tmp-dir {|tmp|
        let art = ($tmp | path join "artifacts")
        mkdir $art
        let leak = $"($LEAK_TOKEN) ($LEAK_ADDR)"
        let env_map = (fake-env $tmp {FAKE_REG_PS_FAIL: "1", FAKE_REG_STDERR: $leak})
        let ctx = (registry-ctx $art (cernbox-sender-cell) "20260101t000000-aabbccdd")
        let lib = (
            $SUITE_PATH | path expand | path dirname | path dirname | path dirname
            | path join "lib/services/reva-registry.nu"
        )
        let runner = ($tmp | path join "run-wait.nu")
        let runner_src = '
use __LIB__ [wait-reva-registries]
let art = __ART__
let ctx = {
  artifacts_base: $art,
  execution_id: "20260101t000000-aabbccdd",
  stack_id: "ocmts-reg-20260101t000000-aabbccdd",
  env_file: "",
  cell: {sender_platform: "cernbox", receiver_platform: "", is_two_party: false},
}
try {
  wait-reva-registries $ctx ["compose.yml"] --timeout 3sec --phase "before-cypress"
  print "UNEXPECTED-SUCCESS"
} catch {|e|
  print $e.msg
}
'
        $runner_src
            | str replace "__LIB__" $lib
            | str replace "__ART__" ($art | to nuon)
            | save --force $runner
        let run = (with-env $env_map {
            ^nu $runner | complete
        })
        let infra = (infra-ctx $art)
        mkdir ($art | path join "meta")
        let wrapped = (with-env $env_map {
            caught-msg {||
                with-infra-fail-cleanup $infra "reva-registry-ready" {||
                    wait-reva-registries $ctx ["compose.yml"] --timeout 3sec --phase "before-cypress"
                } --exit-code 6
            }
        })
        let run_meta = (open ($art | path join "meta/run.json"))
        let blob = $"($run.stdout)\n($run.stderr)\n($wrapped)\n($run_meta.error? | default "")"
        [
            (assert-string-contains $run.stdout "compose-query"
                "docker failure becomes the fixed compose-query reason")
            (assert-truthy (not ($blob | str contains $LEAK_TOKEN))
                "fixture token is absent from console, terminal metadata, and the error")
            (assert-truthy (not ($blob | str contains $LEAK_ADDR))
                "fixture address is absent from console, terminal metadata, and the error")
            (assert-eq $run_meta.status "infra-failed"
                "a registry failure records infra-failed")
            (assert-eq $run_meta.exit_code 6
                "a Nu-style registry failure keeps the requested exit code")
            (assert-truthy (not ((receipt-file $art) | path exists))
                "a leaking docker failure writes no receipt")
        ]
    }
}

def test-infra-fail-clamp-and-cleanup [] {
    test-log "\n[test-infra-fail-clamp-and-cleanup]"
    with-tmp-dir {|tmp|
        let art = ($tmp | path join "artifacts")
        mkdir ($art | path join "meta")
        let ctx = (infra-ctx $art)
        let nu_msg = (caught-msg {||
            with-infra-fail-cleanup $ctx "nu-validation" {||
                error make {msg: "nu validation"}
            } --exit-code 4
        })
        let nu_meta = (open ($art | path join "meta/run.json"))
        let ext_msg = (caught-msg {||
            with-infra-fail-cleanup $ctx "external" {||
                ^sh -c "exit 17"
            } --exit-code 4
        })
        let ext_meta = (open ($art | path join "meta/run.json"))
        let one_meta_box = (caught-msg {||
            with-infra-fail-cleanup $ctx "external-one" {||
                ^sh -c "exit 1"
            } --exit-code 4
        })
        let one_meta = (open ($art | path join "meta/run.json"))
        let env_map = (fake-env $tmp {})
        let marker = ($tmp | path join "cypress-ran")
        let reg_ctx = (registry-ctx $art (cernbox-sender-cell) "20260101t000000-aabbccdd")
        let cleanup_msg = (with-env $env_map {
            caught-msg {||
                with-infra-fail-cleanup $ctx "reva-registry-ready" {||
                    wait-reva-registries $reg_ctx ["compose.yml"] --timeout 0sec --phase "after-cypress"
                    "ran" | save --force $marker
                } --exit-code 4 --base-files ["compose.yml"]
            }
        })
        let cleanup_meta = (open ($art | path join "meta/run.json"))
        let log = (read-log $tmp)
        [
            (assert-eq $nu_meta.exit_code 4
                "a Nu error records the requested code, not 0 or the synthetic 1")
            (assert-eq $nu_meta.status "infra-failed" "a Nu error is infra-failed")
            (assert-string-contains $nu_msg "nu validation" "the Nu error text is preserved")
            (assert-eq $ext_meta.exit_code 17 "external exit 17 is preserved")
            (assert-string-contains $ext_msg "External command had a non-zero exit code"
                "external failure keeps the external error text")
            (assert-eq $one_meta.exit_code 1 "external exit 1 is preserved")
            (assert-truthy (($one_meta_box | str length) > 0) "external exit 1 still fails the action")
            (assert-truthy (not ($marker | path exists))
                "a failed registry wait does not continue into Cypress")
            (assert-eq $cleanup_meta.status "infra-failed"
                "post-run registry failure stays infra-failed")
            (assert-eq $cleanup_meta.phase "reva-registry-ready"
                "post-run registry failure records the registry phase")
            (assert-eq $cleanup_meta.exit_code 4
                "post-run registry failure uses the requested exit code")
            (assert-truthy ($log | str contains " down")
                "registry failure still runs compose down cleanup")
            (assert-string-contains $cleanup_msg "timeout"
                "cleanup failure text is the fixed timeout reason")
        ]
    }
}

def test-container-network-keys [] {
    test-log "\n[test-container-network-keys]"
    let compat_net = $"($EXEC_PROJECT)_ocm-net"
    let compat = (with-tmp-dir {|tmp|
        let art = ($tmp | path join "artifacts")
        mkdir $art
        let env_map = (fake-env $tmp {} $compat_net $EXEC_PROJECT)
        let row = (open ($tmp | path join "fix" "inspect.json") | first)
        let keys = ($row.NetworkSettings.Networks | columns)
        let label = ($row.Config.Labels."com.docker.compose.project")
        let ctx = (registry-ctx $art (cernbox-sender-cell) "20261007t033844-c5e486b4")
        let msg = (with-env $env_map {
            caught-msg {||
                wait-reva-registries $ctx ["compose.yml"] --timeout 20sec --phase "before-cypress"
            }
        })
        let party = if ($msg | is-empty) {
            open (receipt-file $art) | get phases | get before-cypress | get parties | first
        } else {
            {}
        }
        [
            (assert-eq $keys [$compat_net]
                "compat fixture network key ends with _ocm-net")
            (assert-eq $label $EXEC_PROJECT
                "compat fixture keeps a project label that is not the network key")
            (assert-truthy ($compat_net != $EXEC_PROJECT)
                "compat network key is not the project label")
            (assert-eq $msg ""
                "an _ocm-net network key still reaches readiness")
            (assert-eq ($party.healthy? | default false) true
                "compat network party is healthy")
            (assert-eq ($party.processes? | default 0) 12
                "compat network resolves all 12 Reva addresses")
        ]
    })
    let missing = (with-tmp-dir {|tmp|
        let art = ($tmp | path join "artifacts")
        mkdir $art
        let env_map = (fake-env $tmp {} "bridge" $EXEC_PROJECT)
        let row = (open ($tmp | path join "fix" "inspect.json") | first)
        let keys = ($row.NetworkSettings.Networks | columns)
        let ctx = (registry-ctx $art (cernbox-sender-cell) "20261007t033845-c5e486b4")
        let msg = (with-env $env_map {
            caught-msg {||
                wait-reva-registries $ctx ["compose.yml"] --timeout 6sec --phase "before-cypress"
            }
        })
        [
            (assert-eq $keys ["bridge"]
                "negative fixture network key matches neither project nor ocm-net")
            (assert-eq $msg "Reva service registry readiness failed: sender:missing-ip"
                "an unrelated network key fails with missing-ip")
            (assert-truthy (not ((receipt-file $art) | path exists))
                "missing-ip writes no receipt")
        ]
    })
    let blank = (with-tmp-dir {|tmp|
        let art = ($tmp | path join "artifacts")
        mkdir $art
        let env_map = (fake-env $tmp {})
        blank-fixture-ips $tmp
        let stored = (
            open ($tmp | path join "fix" "inspect.json")
            | first
            | get NetworkSettings.Networks
            | get $EXEC_PROJECT
            | get IPAddress
        )
        let ctx = (registry-ctx $art (cernbox-sender-cell) "20261007t033846-c5e486b4")
        let msg = (with-env $env_map {
            caught-msg {||
                wait-reva-registries $ctx ["compose.yml"] --timeout 6sec --phase "before-cypress"
            }
        })
        [
            (assert-eq $stored "   "
                "blank address fixture keeps whitespace in IPAddress")
            (assert-eq $msg "Reva service registry readiness failed: sender:missing-ip"
                "a whitespace execution-network address fails with missing-ip")
            (assert-truthy (not ((receipt-file $art) | path exists))
                "a blank execution-network address writes no receipt")
        ]
    })
    [$compat $missing $blank] | flatten
}

def main [] {
    test-log "=== services/cernbox-registry tests ==="
    let results = (
        (test-registry-parties)
        | append (test-registry-parties-non-cernbox-no-docker)
        | append (test-readiness-healthy-and-js-off)
        | append (test-readiness-bucket-ttl-messages-watchers)
        | append (test-readiness-connections)
        | append (test-wait-timeout-and-compose-query)
        | append (test-wait-restarts-and-retries)
        | append (test-wait-samples-disagree)
        | append (test-wait-receipt-phases)
        | append (test-container-network-keys)
        | append (test-wait-safe-docker-errors)
        | append (test-infra-fail-clamp-and-cleanup)
    ) | flatten
    run-suite "services/cernbox-registry" $SUITE_PATH $results
}
