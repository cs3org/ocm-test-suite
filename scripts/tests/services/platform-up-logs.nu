# Source-contract tests for one-party full-project platform-up and all-service
# log collection. Run: nu scripts/tests/services/platform-up-logs.nu

const SUITE_PATH = path self

use ../../lib/compose/logs.nu [collect-service-logs]
use ../../domains/artifacts/collect.nu [
    logs-cache-covers-compose-project
    missing-or-empty-expected-service-logs
]
use ../../lib/services/infra-fail.nu [with-infra-fail-cleanup]
use ../../lib/services/lifecycle.nu [do-compose-up]
use ../../lib/services/postrun-artifacts.nu [collect-run-artifacts]
use ../../lib/time/utc.nu [utc-now]
use ../../lib/services/wait-services.nu [platform-up-wait-services]
use ../../lib/run/flow-ids.nu [WEBAPP_SHARE_FLOW_ID is-webapp-share-flow]
use ../../lib/tests/assert.nu *
use ../../lib/tests/fixtures.nu [with-tmp-dir]
use ../../lib/tests/runner.nu [run-suite]

# Install a PATH-first docker shim driven by FAKE_DOCKER_* env vars so
# collect-service-logs runtime branches can be exercised without a daemon.
def path-prepend [prefix: string] {
    [$prefix] | append $env.PATH
}

def write-fake-docker [bin_dir: string] {
    let script = $"#!/bin/sh
record_order\(\) {
  if [ -n \"\${FAKE_DOCKER_ORDER_RECORD:-}\" ]; then
    printf '%s\\n' \"\$1\" >> \"\$FAKE_DOCKER_ORDER_RECORD\"
  fi
}
case \"\$*\" in
  *\"network inspect\"*)
    exit 1
    ;;
  *\"ps -a\"*)
    record_order collect-ps
    if [ -n \"\${FAKE_DOCKER_PS_STDOUT:-}\" ]; then
      printf '%b' \"\$FAKE_DOCKER_PS_STDOUT\"
    fi
    exit \${FAKE_DOCKER_PS_EXIT:-0}
    ;;
  *\"config --services\"*)
    if [ -n \"\${FAKE_DOCKER_CONFIG_FAIL_AFTER_LOGS:-}\" ] && [ -n \"\${FAKE_DOCKER_ORDER_RECORD:-}\" ] && [ -f \"\$FAKE_DOCKER_ORDER_RECORD\" ] && grep -q collect-logs \"\$FAKE_DOCKER_ORDER_RECORD\" 2>/dev/null; then
      record_order collect-config-services
      printf '%s' \"\${FAKE_DOCKER_CONFIG_STDERR:-config --services failed}\" >&2
      exit \${FAKE_DOCKER_CONFIG_EXIT:-1}
    fi
    fail_from=\"\${FAKE_DOCKER_CONFIG_FAIL_FROM:-}\"
    if [ -n \"\$fail_from\" ] && [ -n \"\${FAKE_DOCKER_ORDER_RECORD:-}\" ] && [ -f \"\$FAKE_DOCKER_ORDER_RECORD\" ]; then
      n=\$\(grep -c collect-config-services \"\$FAKE_DOCKER_ORDER_RECORD\" 2>/dev/null || echo 0\)
      n=\$\(\(n + 1\)\)
      if [ \"\$n\" -ge \"\$fail_from\" ]; then
        record_order collect-config-services
        printf '%s' \"\${FAKE_DOCKER_CONFIG_STDERR:-config --services failed}\" >&2
        exit \${FAKE_DOCKER_CONFIG_EXIT:-1}
      fi
    fi
    record_order collect-config-services
    if [ \"\${FAKE_DOCKER_CONFIG_FAIL:-}\" = \"1\" ]; then
      printf '%s' \"\${FAKE_DOCKER_CONFIG_STDERR:-config --services failed}\" >&2
      exit \${FAKE_DOCKER_CONFIG_EXIT:-1}
    fi
    if [ -n \"\${FAKE_DOCKER_CONFIG_STDOUT:-}\" ]; then
      printf '%b' \"\$FAKE_DOCKER_CONFIG_STDOUT\"
    fi
    exit 0
    ;;
  *\" config\"*)
    record_order cleanup-config
    printf 'services:\\n  web:\\n    image: fake\\n'
    exit 0
    ;;
  *\" logs \"*)
    record_order collect-logs
    if [ -n \"\${FAKE_DOCKER_LOGS_STDOUT:-}\" ]; then
      printf '%b' \"\$FAKE_DOCKER_LOGS_STDOUT\"
    fi
    if [ -n \"\${FAKE_DOCKER_LOGS_STDERR:-}\" ]; then
      printf '%b' \"\$FAKE_DOCKER_LOGS_STDERR\" >&2
    fi
    exit \${FAKE_DOCKER_LOGS_EXIT:-0}
    ;;
  *\" up -d --wait\"*)
    if [ -n \"\${FAKE_DOCKER_UP_RECORD:-}\" ]; then
      printf '%s' \"\$*\" > \"\$FAKE_DOCKER_UP_RECORD\"
    fi
    if [ \"\${FAKE_DOCKER_UP_FAIL:-}\" = \"1\" ]; then
      printf '%s' \"\${FAKE_DOCKER_UP_STDERR:-compose up failed}\" >&2
      exit \${FAKE_DOCKER_UP_EXIT:-1}
    fi
    exit \${FAKE_DOCKER_UP_EXIT:-0}
    ;;
  *\" down\"*)
    record_order cleanup-down
    exit 0
    ;;
  *)
    echo \"fake-docker: unhandled: \$*\" >&2
    exit 99
    ;;
esac
"
    $script | save ($bin_dir | path join "docker")
    ^chmod +x ($bin_dir | path join "docker")
}

def fake-docker-path [base: string] {
    let bin_dir = ($base | path join "_fake_bin")
    mkdir $bin_dir
    write-fake-docker $bin_dir
    $bin_dir
}

def with-fake-docker-path [base: string, fake_env: record, closure: closure] {
    let bin_dir = (fake-docker-path $base)
    with-env ($fake_env | merge { PATH: (path-prepend $bin_dir) }) {
        do $closure
    }
}

def run-collect-with-fake-docker [
    fake_env: record,
    artifacts_base: string,
    stack_id: string,
    compose_files: list<string>,
    services: list<string>,
] {
    with-fake-docker-path $artifacts_base $fake_env {
        collect-service-logs $artifacts_base $stack_id $compose_files $services
    }
}

def ocmts-repo-root [] {
    $SUITE_PATH | path dirname | path join ".." ".." ".." | path expand
}

const COLLECT_MAIN_EXEC_ID = "20260101t120000-aabbccdd"
const COLLECT_MAIN_STACK_ID = "collect-main-test"

def write-collect-main-fixture [ocmts_root: string] {
    let base = (
        $ocmts_root
        | path join "artifacts" "login" "nextcloud-v34" $COLLECT_MAIN_EXEC_ID
    )
    mkdir ($base | path join "compose")
    mkdir ($base | path join "meta")
    mkdir ($base | path join "docker" "logs")
    {
        schema_version: 1,
        stack_id: $COLLECT_MAIN_STACK_ID,
        base: "config/compose/base.yml",
        applied_inputs: ["config/compose/base.yml"],
    } | to json | save ($base | path join "compose" "manifest.v1.json")
    {
        schema_version: 1,
        id: $COLLECT_MAIN_EXEC_ID,
        execution_id: $COLLECT_MAIN_EXEC_ID,
        stack_id: $COLLECT_MAIN_STACK_ID,
        status: "failed",
    } | to json | save ($base | path join "meta" "run.json")
    $COLLECT_MAIN_EXEC_ID | save (
        $ocmts_root | path join "artifacts" "login" "nextcloud-v34" "LAST_EXECUTION_ID"
    )
    $base
}

def with-ocmts-collect-root [closure: closure] {
    with-tmp-dir {|tmpdir|
        let repo = (ocmts-repo-root)
        if ($tmpdir | path join "config" | path exists) {
            error make {msg: "with-ocmts-collect-root: config path already exists"}
        }
        ^ln -s ($repo | path join "config") ($tmpdir | path join "config")
        with-env { OCMTS_ROOT: $tmpdir } { do $closure $tmpdir $repo }
    }
}

def run-collect-main-entry [
    ocmts_root: string,
    repo_root: string,
    fake_env: record,
] {
    let bin_dir = (fake-docker-path $ocmts_root)
    let script = ($repo_root | path join "scripts/domains/artifacts/collect.nu")
    let nu_bin = (which nu | get path.0? | default "/usr/bin/nu")
    with-env ($fake_env | merge {
        PATH: (path-prepend $bin_dir),
        OCMTS_ROOT: $ocmts_root,
    }) {
        (^$nu_bin $script --flow login --sender-platform nextcloud --sender-version v34 --execution-id $COLLECT_MAIN_EXEC_ID --include-logs | complete)
    }
}

def read-src [path: string] {
    open --raw $path
}

def test-lifecycle-empty-wait-services-full-project [] {
    test-log "\n[test-lifecycle-empty-wait-services-full-project]"
    let src = (read-src "scripts/lib/services/lifecycle.nu")
    [
        (assert-truthy ($src | str contains "wait_services: compose service names")
            "lifecycle.nu documents wait_services contract")
        (assert-truthy ($src | str contains "list means no service targets")
            "lifecycle.nu states empty wait_services means full project")
        (assert-truthy ($src | str contains "up -d --wait ...$wait_services")
            "do-compose-up splats wait_services (empty list = full project)")
        (assert-truthy (not ($src | str contains "if ($wait_services | is-empty)"))
            "do-compose-up no longer branches on empty wait_services")
    ]
}

def test-up-one-party-no-sender-only-target [] {
    test-log "\n[test-up-one-party-no-sender-only-target]"
    let src = (read-src "scripts/domains/services/up.nu")
    [
        (assert-truthy (not ($src | str contains '{ ["sender"] }'))
            "services/up.nu no longer hardcodes one-party wait_services = [sender]")
        (assert-truthy ($src | str contains "use ../../lib/services/wait-services.nu [platform-up-wait-services]")
            "services/up.nu imports platform-up-wait-services helper")
        (assert-truthy ($src | str contains "platform-up-wait-services $ctx.is_two_party $ctx.cell.flow_id")
            "services/up.nu delegates wait_services to platform-up-wait-services")
        (assert-truthy ($src | str contains "up -d --wait ...$wait_services")
            "services/up.nu splats wait_services for compose up")
        (assert-truthy (not ($src | str contains "if ($wait_services | is-empty)"))
            "services/up.nu no longer branches on empty wait_services")
    ]
}

def test-up-open-one-party-full-project [] {
    test-log "\n[test-up-open-one-party-full-project]"
    let src = (read-src "scripts/domains/services/up-open.nu")
    [
        (assert-truthy (not ($src | str contains '{ ["sender"] }'))
            "services/up-open.nu no longer hardcodes one-party wait_services = [sender]")
        (assert-truthy ($src | str contains "use ../../lib/services/wait-services.nu [platform-up-wait-services]")
            "services/up-open.nu imports platform-up-wait-services helper")
        (assert-truthy ($src | str contains "platform-up-wait-services $ctx.is_two_party $ctx.cell.flow_id")
            "services/up-open.nu delegates wait_services to platform-up-wait-services")
        (assert-truthy ($src | str contains "up -d --wait ...$wait_services")
            "services/up-open.nu splats wait_services for platform compose up")
        (assert-truthy (not ($src | str contains "if ($wait_services | is-empty)"))
            "services/up-open.nu no longer branches on empty wait_services")
        (assert-truthy ($src | str contains "def collect-open-failure-logs")
            "services/up-open.nu defines a shared failure-log helper")
        (assert-truthy ($src | str contains "collect-service-logs $ctx.artifacts_base $ctx.stack_id $compose_files []")
            "services/up-open.nu helper uses all-services discovery")
        (assert-truthy ($src | str contains 'collect-open-failure-logs $ctx $base_files "platform-up"')
            "platform-up failure collects logs before teardown")
        (assert-truthy ($src | str contains 'collect-open-failure-logs $ctx $base_files "compose-validate-dev"')
            "compose-validate-dev failure collects logs before teardown")
        (assert-truthy ($src | str contains 'collect-open-failure-logs $ctx $dev_files "cypress-dev-up"')
            "cypress-dev-up failure collects logs before teardown")
        (assert-truthy ($src | str contains 'collect-open-failure-logs $ctx $dev_files "cypress-dev-port-exit"')
            "port lookup nonzero-exit failure collects logs before teardown")
        (assert-truthy ($src | str contains 'collect-open-failure-logs $ctx $dev_files "cypress-dev-port-invalid"')
            "port lookup invalid-port failure collects logs before teardown")
        (assert-truthy ($src | str contains "up -d cypress_dev")
            "services/up-open.nu still starts cypress_dev separately")
    ]
}

def test-up-run-one-party-and-failure-logs [] {
    test-log "\n[test-up-run-one-party-and-failure-logs]"
    let src = (read-src "scripts/domains/services/up-run.nu")
    [
        (assert-truthy (not ($src | str contains '{ ["sender"] }'))
            "services/up-run.nu no longer hardcodes one-party wait_services = [sender]")
        (assert-truthy ($src | str contains '} else { [] }')
            "services/up-run.nu one-party wait_services is empty list")
        (assert-truthy ($src | str contains "collect-service-logs $ctx.artifacts_base $ctx.stack_id $base_files []")
            "platform-up failure collects logs for all project services")
    ]
}

def test-platform-up-wait-services-helper [] {
    test-log "\n[test-platform-up-wait-services-helper]"
    let wait_src = (read-src "scripts/lib/services/wait-services.nu")
    [
        (assert-eq (platform-up-wait-services false "") []
            "one-party wait_services is empty list")
        (assert-eq (platform-up-wait-services false "login") []
            "one-party login wait_services is empty list")
        (assert-eq (platform-up-wait-services true "share-with") ["sender" "receiver" "mitm"]
            "two-party default wait_services is sender/receiver/mitm")
        (assert-eq (platform-up-wait-services true $WEBAPP_SHARE_FLOW_ID) ["sender" "receiver" "mitm" "sender-hub"]
            "webapp-share two-party wait_services appends sender-hub")
        (assert-truthy (is-webapp-share-flow $WEBAPP_SHARE_FLOW_ID)
            "is-webapp-share-flow recognizes WEBAPP_SHARE_FLOW_ID")
        (assert-truthy (not (is-webapp-share-flow "share-with"))
            "is-webapp-share-flow rejects non-webapp-share flows")
        (assert-truthy ($wait_src | str contains "is-webapp-share-flow")
            "wait-services.nu routes webapp-share via flow-ids helper")
        (assert-truthy (not ($wait_src | str contains '== "webapp-share"'))
            "wait-services.nu does not inline webapp-share string compare")
    ]
}

def test-logs-empty-services-means-compose-project [] {
    test-log "\n[test-logs-empty-services-means-compose-project]"
    let src = (read-src "scripts/lib/compose/logs.nu")
    [
        (assert-truthy ($src | str contains "An empty services list means all services")
            "logs.nu documents empty services contract")
        (assert-truthy ($src | str contains "config --services")
            "logs.nu resolves empty services from compose project definition")
        (assert-truthy (not ($src | str contains "let target_services = if ($services | is-empty) { $known }"))
            "logs.nu no longer resolves empty services from container labels only")
    ]
}

def test-collect-service-logs-empty-services-resolves-config [] {
    test-log "\n[test-collect-service-logs-empty-services-resolves-config]"
    with-tmp-dir {|root|
        let artifacts = ($root | path join "artifacts")
        mkdir $artifacts
        let fake_env = {
            FAKE_DOCKER_PS_STDOUT: ""
            FAKE_DOCKER_PS_EXIT: "0"
            FAKE_DOCKER_CONFIG_STDOUT: "alpha\nbeta\n"
        }
        let result = (run-collect-with-fake-docker $fake_env $artifacts "test-stack" [] [])
        let names = ($result.services | get service)
        [
            (assert-truthy $result.ok
                "empty services resolves config targets and writes skipped placeholders")
            (assert-eq ($result.services | length) 2
                "config --services stdout becomes two runtime targets")
            (assert-list-contains $names "alpha" "alpha from compose config --services")
            (assert-list-contains $names "beta" "beta from compose config --services")
            (assert-truthy ($result.services | all {|r| $r.skipped? == true})
                "no matching containers yields skipped records")
            (assert-string-contains
                (open ($artifacts | path join "docker" "logs" "alpha.log") | str trim)
                "SKIPPED: no container found for compose service: alpha"
                "alpha skipped placeholder written to log file")
        ]
    }
}

def test-collect-service-logs-config-services-failure [] {
    test-log "\n[test-collect-service-logs-config-services-failure]"
    with-tmp-dir {|root|
        let artifacts = ($root | path join "artifacts")
        mkdir $artifacts
        let fake_env = {
            FAKE_DOCKER_PS_STDOUT: ""
            FAKE_DOCKER_PS_EXIT: "0"
            FAKE_DOCKER_CONFIG_FAIL: "1"
            FAKE_DOCKER_CONFIG_STDERR: "compose config unavailable"
        }
        let result = (run-collect-with-fake-docker $fake_env $artifacts "test-stack" [] [])
        let err = ($result.services | get 0 | get error)
        [
            (assert-truthy (not $result.ok) "config --services failure sets ok false")
            (assert-eq ($result.services | length) 1
                "config failure returns one aggregate error record")
            (assert-string-contains $err "compose project service list failed"
                "error names compose project service list failure")
            (assert-string-contains $err "compose config unavailable"
                "error includes config --services stderr")
        ]
    }
}

def test-do-compose-up-empty-wait-full-project-runtime [] {
    test-log "\n[test-do-compose-up-empty-wait-full-project-runtime]"
    with-tmp-dir {|root|
        let record = ($root | path join "up-record.txt")
        let fake_env = {
            FAKE_DOCKER_UP_RECORD: $record
            FAKE_DOCKER_UP_EXIT: "0"
        }
        let f_args = ["-f" ($root | path join "compose.yml")]
        let result = (with-fake-docker-path $root $fake_env {
            do-compose-up $f_args "test-stack" [] false ""
        })
        let cmd = (open --raw $record | str trim)
        [
            (assert-null $result "empty wait_services compose up returns null on success")
            (assert-string-contains $cmd "up -d --wait"
                "do-compose-up invokes docker compose up -d --wait")
            (assert-truthy ($cmd | str ends-with "--wait")
                "empty wait_services adds no trailing compose service names")
        ]
    }
}

def test-collect-service-logs-success-write-runtime [] {
    test-log "\n[test-collect-service-logs-success-write-runtime]"
    with-tmp-dir {|root|
        let artifacts = ($root | path join "artifacts")
        mkdir $artifacts
        let fake_env = {
            FAKE_DOCKER_PS_STDOUT: "web\n"
            FAKE_DOCKER_PS_EXIT: "0"
            FAKE_DOCKER_LOGS_STDOUT: "2024-01-01T00:00:00Z web started\n"
            FAKE_DOCKER_LOGS_EXIT: "0"
        }
        let result = (run-collect-with-fake-docker $fake_env $artifacts "test-stack" [] ["web"])
        let row = ($result.services | get 0)
        let log_content = (open ($artifacts | path join "docker" "logs" "web.log") | str trim)
        [
            (assert-truthy $result.ok "successful docker compose logs path keeps ok true")
            (assert-eq ($row.service) "web" "matched container service name preserved")
            (assert-truthy (not ($row.skipped? | default false))
                "existing container is not marked skipped")
            (assert-string-contains $log_content "web started"
                "docker compose logs stdout written to service log file")
        ]
    }
}

def test-collect-run-artifacts-all-services-runtime [] {
    test-log "\n[test-collect-run-artifacts-all-services-runtime]"
    with-tmp-dir {|root|
        let artifacts = ($root | path join "artifacts")
        mkdir $artifacts
        let fake_env = {
            FAKE_DOCKER_PS_STDOUT: "alpha\n"
            FAKE_DOCKER_PS_EXIT: "0"
            FAKE_DOCKER_CONFIG_STDOUT: "alpha\nbeta\n"
            FAKE_DOCKER_LOGS_STDOUT: "alpha runtime log line\n"
            FAKE_DOCKER_LOGS_EXIT: "0"
        }
        with-fake-docker-path $artifacts $fake_env {
            collect-run-artifacts $artifacts "test-stack" [] false
        }
        let alpha_log = (open ($artifacts | path join "docker" "logs" "alpha.log") | str trim)
        let beta_log = (open ($artifacts | path join "docker" "logs" "beta.log") | str trim)
        [
            (assert-string-contains $alpha_log "alpha runtime log line"
                "collect-run-artifacts empty services collects logs for running service")
            (assert-string-contains $beta_log "SKIPPED: no container found for compose service: beta"
                "collect-run-artifacts empty services writes skipped placeholder for missing service")
        ]
    }
}

def test-collect-service-logs-missing-container-skipped [] {
    test-log "\n[test-collect-service-logs-missing-container-skipped]"
    with-tmp-dir {|root|
        let artifacts = ($root | path join "artifacts")
        mkdir $artifacts
        let fake_env = {
            FAKE_DOCKER_PS_STDOUT: "other-svc\n"
            FAKE_DOCKER_PS_EXIT: "0"
        }
        let result = (run-collect-with-fake-docker $fake_env $artifacts "test-stack" [] ["web"])
        let row = ($result.services | get 0)
        [
            (assert-truthy $result.ok "missing container skipped path keeps per-service ok true")
            (assert-eq ($row.service) "web" "caller service name preserved")
            (assert-truthy ($row.skipped?) "skipped flag set when compose label missing")
            (assert-string-contains ($row.note?)
                "SKIPPED: no container found for compose service: web"
                "note explains missing container")
            (assert-string-contains
                (open ($row.path) | str trim)
                "SKIPPED: no container found for compose service: web"
                "skipped note written to service log path")
        ]
    }
}

def test-postrun-artifacts-all-project-services [] {
    test-log "\n[test-postrun-artifacts-all-project-services]"
    let src = (read-src "scripts/lib/services/postrun-artifacts.nu")
    [
        (assert-truthy (not ($src | str contains "sender-db"))
            "postrun-artifacts.nu no longer hardcodes sender-db")
        (assert-truthy (not ($src | str contains "sender-cache"))
            "postrun-artifacts.nu no longer hardcodes sender-cache")
        (assert-truthy ($src | str contains "collect-service-logs $artifacts_base $stack_id $run_files []")
            "postrun-artifacts.nu collects logs from all project services")
    ]
}

def is-compose-top-level-service-line [line: string] {
    not (($line | parse --regex '^  [^\s].+:$' | is-empty))
}

# Return the YAML body for one top-level `services:` entry (2-space key).
def extract-compose-service-block [src: string, service: string] {
    let marker = $"  ($service):"
    let lines = ($src | lines)
    let start = ($lines | enumerate | where {|e| $e.item == $marker} | first)
    if ($start == null) {
        return null
    }
    let tail = ($lines | skip ($start.index + 1))
    let next = ($tail | enumerate | where {|e| (is-compose-top-level-service-line $e.item)} | first)
    let end = if ($next == null) { ($tail | length) } else { $next.index }
    $tail | take $end | str join (char newline)
}

const CERNBOX_BAKED_HEALTH_SERVICES = [
    "sender"
    "sender-idp"
    "sender-revad-gateway"
    "sender-revad-authprovider-oidc"
    "sender-revad-authprovider-machine"
    "sender-revad-authprovider-ocmshares"
    "sender-revad-authprovider-ocmsharecode"
    "sender-revad-authprovider-ocmexchangedtoken"
    "sender-revad-authprovider-publicshares"
    "sender-revad-shareproviders"
    "sender-revad-groupuserproviders"
    "sender-revad-dataprovider-localhome"
    "sender-revad-dataprovider-ocm"
    "sender-revad-dataprovider-sciencemesh"
]

def test-cernbox-cookbook-baked-health-contract [] {
    test-log "\n[test-cernbox-cookbook-baked-health-contract]"
    let src = (read-src "config/compose/cookbooks/cernbox.sender.yml")
    mut results = [
        (assert-truthy (not ($src | str contains "sport = :"))
            "cernbox.sender.yml has no inline compose sport = : gRPC probes")
        (assert-truthy (not ($src | str contains "healthcheck:"))
            "cernbox.sender.yml has no compose healthcheck blocks (baked in images)")
    ]
    $results = ($results | append (
        $CERNBOX_BAKED_HEALTH_SERVICES | each {|svc|
            let block = (extract-compose-service-block $src $svc)
            if $svc == "sender" {
                [
                    (assert-not-null $block "sender block exists")
                    (assert-truthy ($block | str contains "sender-idp:")
                        "sender depends_on sender-idp")
                    (assert-truthy ($block | str contains "condition: service_healthy")
                        "sender uses service_healthy for baked-health deps")
                    (assert-truthy ($block | str contains "sender-revad-gateway:")
                        "sender depends_on sender-revad-gateway with service_healthy")
                    (assert-truthy ($block | str contains "sender-revad-dataprovider-localhome:")
                        "sender depends_on dataprovider-localhome with service_healthy")
                ]
            } else if ($svc | str starts-with "sender-revad-") and $svc != "sender-revad-gateway" {
                [
                    (assert-not-null $block $"($svc) block exists")
                    (assert-truthy ($block | str contains "sender-revad-gateway:")
                        $"($svc) depends_on sender-revad-gateway")
                    (assert-truthy ($block | str contains "condition: service_healthy")
                        $"($svc) waits on gateway with service_healthy")
                ]
            } else if $svc == "sender-revad-gateway" {
                [
                    (assert-not-null $block "sender-revad-gateway block exists")
                    (assert-truthy ($block | str contains "sender-idp:")
                        "gateway depends_on sender-idp")
                    (assert-truthy ($block | str contains "condition: service_healthy")
                        "gateway waits on idp with service_healthy")
                ]
            } else {
                [(assert-not-null $block $"($svc) block exists")]
            }
        } | flatten
    ))
    $results
}

def test-infra-fail-collects-logs-before-teardown [] {
    test-log "\n[test-infra-fail-collects-logs-before-teardown]"
    let src = (read-src "scripts/lib/services/infra-fail.nu")
    [
        (assert-truthy ($src | str contains "collect-service-logs $ctx.artifacts_base $ctx.stack_id $base_files []")
            "with-infra-fail-cleanup collects all project logs before compose down")
        (assert-truthy ($src | str contains "cleanup-down $base_files")
            "with-infra-fail-cleanup still tears down after log collection")
    ]
}

def infra-fail-fixture-ctx [artifacts_base: string, stack_id: string] {
    let ts = (utc-now)
    {
        artifacts_base: $artifacts_base,
        execution_id: "20260101t120000-aabbccdd",
        cell: {
            cell_id: "login__nextcloud-v34",
            artifact_name: "cell-login-nextcloud-v34",
            flow_id: "login",
            pair: "nextcloud-v34",
        },
        started_at: $ts,
        stack_id: $stack_id,
        images: null,
        suite_id: "",
        suite_kind: "single",
    }
}

def test-infra-fail-collects-logs-before-teardown-runtime [] {
    test-log "\n[test-infra-fail-collects-logs-before-teardown-runtime]"
    with-tmp-dir {|root|
        let artifacts = ($root | path join "artifacts")
        mkdir ($artifacts | path join "meta")
        mkdir ($artifacts | path join "compose")
        let compose = ($root | path join "compose.yml")
        "services:\n  web:\n    image: fake\n" | save -f $compose
        let order_file = ($root | path join "docker-order.txt")
        let stack_id = "infra-fail-test"
        let ctx = (infra-fail-fixture-ctx $artifacts $stack_id)
        let fake_env = {
            FAKE_DOCKER_ORDER_RECORD: $order_file
            FAKE_DOCKER_PS_STDOUT: ""
            FAKE_DOCKER_PS_EXIT: "0"
            FAKE_DOCKER_CONFIG_STDOUT: "web\n"
        }

        let caught = (try {
            with-fake-docker-path $root $fake_env {
                with-infra-fail-cleanup $ctx "test-phase" {
                    error make {msg: "simulated infra failure"}
                } --base-files [$compose]
            }
            false
        } catch {|_| true})

        let order = if ($order_file | path exists) {
            open --raw $order_file | lines | where {|l| not ($l | is-empty)}
        } else {
            []
        }
        let collect_idx = ($order | enumerate | where {|e| ($e.item | str starts-with "collect")} | first)
        let down_idx = ($order | enumerate | where {|e| $e.item == "cleanup-down"} | first)

        [
            (assert-truthy $caught "with-infra-fail-cleanup re-throws simulated failure")
            (assert-truthy ($collect_idx != null) "collect-service-logs invoked docker during failure cleanup")
            (assert-truthy ($down_idx != null) "cleanup-down invoked docker compose down")
            (assert-truthy ($collect_idx.index < $down_idx.index)
                "log collection docker calls precede compose down")
        ]
    }
}

def test-artifacts-collect-all-services-discovery [] {
    test-log "\n[test-artifacts-collect-all-services-discovery]"
    let src = (read-src "scripts/domains/artifacts/collect.nu")
    [
        (assert-truthy (not ($src | str contains "sender-db"))
            "artifacts collect no longer hardcodes sender-db")
        (assert-truthy (not ($src | str contains "sender-cache"))
            "artifacts collect no longer hardcodes sender-cache")
        (assert-truthy ($src | str contains "let log_services = []")
            "artifacts collect uses empty list for all-services discovery")
        (assert-truthy ($src | str contains "collect-service-logs $base $stack_id $compose_files $log_services")
            "artifacts collect passes empty services to collect-service-logs")
        (assert-truthy ($src | str contains "logs-cache-covers-compose-project")
            "artifacts collect checks full compose service cache coverage")
        (assert-truthy (not ($src | str contains "if $cached > 0"))
            "artifacts collect no longer fast-paths on any cached log file")
    ]
}

def test-artifacts-collect-stack-gone-includes-absent-expected-log [] {
    test-log "\n[test-artifacts-collect-stack-gone-includes-absent-expected-log]"
    with-tmp-dir {|root|
        let artifacts = ($root | path join "artifacts")
        let logs_dir = ($artifacts | path join "docker" "logs")
        mkdir $logs_dir
        # beta.log exists but is empty; alpha.log is absent entirely.
        "" | save ($logs_dir | path join "beta.log")

        let fake_env = {
            FAKE_DOCKER_PS_STDOUT: "alpha\nbeta\n"
            FAKE_DOCKER_PS_EXIT: "0"
            FAKE_DOCKER_CONFIG_STDOUT: "alpha\nbeta\n"
            FAKE_DOCKER_LOGS_STDERR: "no containers found for compose project"
            FAKE_DOCKER_LOGS_EXIT: "1"
        }
        let result = (run-collect-with-fake-docker $fake_env $artifacts "test-stack" [] [])
        let stack_gone = ($result.services | any {|s|
            ((not $s.ok) and (($s.error? | default "") | str contains "no containers"))
        })
        let missing_paths = (missing-or-empty-expected-service-logs $logs_dir ["alpha" "beta"])
        let missing_list = ($missing_paths | each {|p| $"  ($p)"} | str join "\n")
        let err_msg = $"Log collection failed: stack is already torn down. Missing or empty logs:\n($missing_list)"
        let alpha_log = ($logs_dir | path join "alpha.log")
        [
            (assert-truthy (not $result.ok)
                "compose logs failure with no containers sets ok false")
            (assert-truthy $stack_gone
                "no containers stderr triggers stack-gone detection")
            (assert-truthy (not ($alpha_log | path exists))
                "alpha.log remains absent before stack-gone diagnostic")
            (assert-string-contains $err_msg $alpha_log
                "stack-gone missing list includes absent expected alpha.log")
            (assert-string-contains $err_msg ($logs_dir | path join "beta.log")
                "stack-gone missing list includes zero-byte beta.log")
        ]
    }
}

def test-artifacts-collect-zero-byte-cache-no-fast-path [] {
    test-log "\n[test-artifacts-collect-zero-byte-cache-no-fast-path]"
    with-tmp-dir {|root|
        let artifacts = ($root | path join "artifacts")
        let logs_dir = ($artifacts | path join "docker" "logs")
        mkdir $logs_dir
        # Both expected logs exist but are zero-byte; must not satisfy cache coverage.
        "" | save ($logs_dir | path join "alpha.log")
        "" | save ($logs_dir | path join "beta.log")

        let order_file = ($root | path join "docker-order.txt")
        let fake_env = {
            FAKE_DOCKER_ORDER_RECORD: $order_file
            FAKE_DOCKER_PS_STDOUT: "alpha\nbeta\n"
            FAKE_DOCKER_PS_EXIT: "0"
            FAKE_DOCKER_CONFIG_STDOUT: "alpha\nbeta\n"
            FAKE_DOCKER_LOGS_STDOUT: "zero-byte cache backfill line\n"
            FAKE_DOCKER_LOGS_EXIT: "0"
        }

        let run = (with-fake-docker-path $artifacts $fake_env {
            let cache_complete = (
                logs-cache-covers-compose-project $artifacts "test-stack" []
            )
            let missing_before = (
                missing-or-empty-expected-service-logs $logs_dir ["alpha" "beta"]
            )
            let result = if not $cache_complete {
                collect-service-logs $artifacts "test-stack" [] []
            } else {
                null
            }
            {
                cache_complete: $cache_complete
                missing_before: $missing_before
                result: $result
            }
        })

        let order = if ($order_file | path exists) {
            open --raw $order_file | lines | where {|l| not ($l | is-empty)}
        } else {
            []
        }
        let alpha_path = ($logs_dir | path join "alpha.log")
        let beta_path = ($logs_dir | path join "beta.log")
        let alpha_log = (open $alpha_path | str trim)
        let beta_log = (open $beta_path | str trim)
        let alpha_size = (ls $alpha_path | get 0 | get size)
        let beta_size = (ls $beta_path | get 0 | get size)
        [
            (assert-truthy (not $run.cache_complete)
                "zero-byte cached logs do not satisfy full compose service coverage")
            (assert-eq ($run.missing_before | length) 2
                "zero-byte logs count as missing before live backfill")
            (assert-not-null $run.result
                "zero-byte cache triggers live collect-service-logs instead of fast-path")
            (assert-truthy $run.result.ok
                "live collection backfills zero-byte cached logs")
            (assert-list-contains $order "collect-ps"
                "live path invokes docker ps for stack availability")
            (assert-list-contains $order "collect-config-services"
                "live path resolves compose project services from config")
            (assert-list-contains $order "collect-logs"
                "live path invokes docker compose logs for backfill")
            (assert-truthy ($alpha_size != 0b)
                "alpha.log backfilled to non-zero size")
            (assert-truthy ($beta_size != 0b)
                "beta.log backfilled to non-zero size")
            (assert-string-contains $alpha_log "zero-byte cache backfill line"
                "alpha zero-byte cache overwritten by live collection")
            (assert-string-contains $beta_log "zero-byte cache backfill line"
                "beta zero-byte cache overwritten by live collection")
        ]
    }
}

def test-artifacts-collect-main-complete-cache-fast-path [] {
    test-log "\n[test-artifacts-collect-main-complete-cache-fast-path]"
    with-ocmts-collect-root {|ocmts_root, repo_root|
        let base = (write-collect-main-fixture $ocmts_root)
        let logs_dir = ($base | path join "docker" "logs")
        "alpha cached line" | save ($logs_dir | path join "alpha.log")
        "beta cached line" | save ($logs_dir | path join "beta.log")

        let order_file = ($ocmts_root | path join "docker-order.txt")
        let fake_env = {
            FAKE_DOCKER_ORDER_RECORD: $order_file
            FAKE_DOCKER_CONFIG_STDOUT: "alpha\nbeta\n"
        }
        let run = (run-collect-main-entry $ocmts_root $repo_root $fake_env)
        let order = if ($order_file | path exists) {
            open --raw $order_file | lines | where {|l| not ($l | is-empty)}
        } else {
            []
        }
        let out = ($run.stdout | str trim)
        [
            (assert-eq $run.exit_code 0
                "collect.nu main exits 0 on complete-cache fast path")
            (assert-string-contains $out "Collected:"
                "collect.nu main prints Collected lines from cache")
            (assert-list-contains $order "collect-config-services"
                "cache coverage probes compose project services once")
            (assert-truthy (not ($order | any {|l| $l == "collect-logs"}))
                "complete cache skips live docker compose logs")
            (assert-truthy (not ($order | any {|l| $l == "collect-ps"}))
                "complete cache skips docker ps for live collection")
        ]
    }
}

def test-artifacts-collect-main-stack-gone-error [] {
    test-log "\n[test-artifacts-collect-main-stack-gone-error]"
    with-ocmts-collect-root {|ocmts_root, repo_root|
        let base = (write-collect-main-fixture $ocmts_root)
        let logs_dir = ($base | path join "docker" "logs")
        "" | save ($logs_dir | path join "beta.log")

        let fake_env = {
            FAKE_DOCKER_PS_STDOUT: "alpha\nbeta\n"
            FAKE_DOCKER_PS_EXIT: "0"
            FAKE_DOCKER_CONFIG_STDOUT: "alpha\nbeta\n"
            FAKE_DOCKER_LOGS_STDERR: "no containers found for compose project"
            FAKE_DOCKER_LOGS_EXIT: "1"
        }
        let run = (run-collect-main-entry $ocmts_root $repo_root $fake_env)
        let err = ([$run.stderr $run.stdout] | str join "\n" | str trim)
        let alpha_log = ($logs_dir | path join "alpha.log")
        [
            (assert-truthy ($run.exit_code != 0)
                "collect.nu main exits non-zero when stack is gone")
            (assert-string-contains $err "stack is already torn down"
                "collect.nu main emits stack-gone error")
            (assert-string-contains $err "Missing or empty logs"
                "stack-gone error names missing expected logs when discovery works")
            (assert-string-contains $err "alpha.log"
                "stack-gone error lists absent expected alpha.log")
            (assert-string-contains $err "beta.log"
                "stack-gone error lists zero-byte beta.log")
        ]
    }
}

def test-artifacts-collect-main-stack-gone-discovery-unavailable [] {
    test-log "\n[test-artifacts-collect-main-stack-gone-discovery-unavailable]"
    with-ocmts-collect-root {|ocmts_root, repo_root|
        let base = (write-collect-main-fixture $ocmts_root)
        let logs_dir = ($base | path join "docker" "logs")
        "alpha cached line" | save ($logs_dir | path join "alpha.log")
        "" | save ($logs_dir | path join "beta.log")

        let fake_env = {
            FAKE_DOCKER_PS_STDOUT: "alpha\nbeta\n"
            FAKE_DOCKER_PS_EXIT: "0"
            FAKE_DOCKER_CONFIG_STDOUT: "alpha\nbeta\n"
            FAKE_DOCKER_CONFIG_FAIL_AFTER_LOGS: "1"
            FAKE_DOCKER_ORDER_RECORD: ($ocmts_root | path join "docker-order.txt")
            FAKE_DOCKER_CONFIG_STDERR: "compose config unavailable on diagnostic"
            FAKE_DOCKER_LOGS_STDERR: "no containers found for compose project"
            FAKE_DOCKER_LOGS_EXIT: "1"
        }
        let run = (run-collect-main-entry $ocmts_root $repo_root $fake_env)
        let err = ([$run.stderr $run.stdout] | str join "\n" | str trim)
        let alpha_log = ($logs_dir | path join "alpha.log")
        [
            (assert-truthy ($run.exit_code != 0)
                "collect.nu main exits non-zero for stack-gone with discovery failure")
            (assert-string-contains $err "stack is already torn down"
                "stack-gone error still emitted")
            (assert-string-contains $err "is unavailable"
                "diagnostic names unavailable compose service discovery")
            (assert-string-contains $err "Zero-byte cached logs"
                "diagnostic reports zero-byte cached logs when discovery fails")
            (assert-string-contains $err "beta.log"
                "diagnostic lists only known zero-byte cached logs")
            (assert-truthy (not ($err | str contains $alpha_log))
                "diagnostic does not claim absent alpha.log is a missing expected log")
            (assert-truthy (not ($err | str contains "Missing or empty logs"))
                "diagnostic avoids missing-expected wording when discovery failed")
        ]
    }
}

def test-artifacts-collect-partial-cache-rerun-backfills [] {
    test-log "\n[test-artifacts-collect-partial-cache-rerun-backfills]"
    with-tmp-dir {|root|
        let artifacts = ($root | path join "artifacts")
        let logs_dir = ($artifacts | path join "docker" "logs")
        mkdir $logs_dir
        "alpha cached line" | save ($logs_dir | path join "alpha.log")

        let fake_env = {
            FAKE_DOCKER_PS_STDOUT: "alpha\nbeta\n"
            FAKE_DOCKER_PS_EXIT: "0"
            FAKE_DOCKER_CONFIG_STDOUT: "alpha\nbeta\n"
            FAKE_DOCKER_LOGS_STDOUT: "beta runtime log line\n"
            FAKE_DOCKER_LOGS_EXIT: "0"
        }

        let run = (with-fake-docker-path $artifacts $fake_env {
            let cache_complete = (
                logs-cache-covers-compose-project $artifacts "test-stack" []
            )
            let result = if not $cache_complete {
                collect-service-logs $artifacts "test-stack" [] []
            } else {
                null
            }
            {cache_complete: $cache_complete, result: $result}
        })
        let cache_complete = $run.cache_complete
        let result = $run.result

        let alpha_log = (open ($logs_dir | path join "alpha.log") | str trim)
        let beta_log = (open ($logs_dir | path join "beta.log") | str trim)
        [
            (assert-truthy (not $cache_complete)
                "partial cache does not satisfy full compose service coverage")
            (assert-not-null $result
                "partial cache triggers live collect-service-logs backfill")
            (assert-truthy $result.ok
                "backfill collects logs for all compose project services")
            (assert-string-contains $alpha_log "beta runtime log line"
                "backfill refreshes alpha.log from docker compose logs")
            (assert-string-contains $beta_log "beta runtime log line"
                "backfill writes missing beta.log")
        ]
    }
}

def main [] {
    test-log "=== services/platform-up-logs contract tests ==="
    let results = (
        (test-lifecycle-empty-wait-services-full-project)
        | append (test-up-one-party-no-sender-only-target)
        | append (test-up-open-one-party-full-project)
        | append (test-up-run-one-party-and-failure-logs)
        | append (test-platform-up-wait-services-helper)
        | append (test-logs-empty-services-means-compose-project)
        | append (test-collect-service-logs-empty-services-resolves-config)
        | append (test-collect-service-logs-config-services-failure)
        | append (test-do-compose-up-empty-wait-full-project-runtime)
        | append (test-collect-service-logs-success-write-runtime)
        | append (test-collect-run-artifacts-all-services-runtime)
        | append (test-collect-service-logs-missing-container-skipped)
        | append (test-postrun-artifacts-all-project-services)
        | append (test-cernbox-cookbook-baked-health-contract)
        | append (test-infra-fail-collects-logs-before-teardown)
        | append (test-infra-fail-collects-logs-before-teardown-runtime)
        | append (test-artifacts-collect-all-services-discovery)
        | append (test-artifacts-collect-stack-gone-includes-absent-expected-log)
        | append (test-artifacts-collect-zero-byte-cache-no-fast-path)
        | append (test-artifacts-collect-main-complete-cache-fast-path)
        | append (test-artifacts-collect-main-stack-gone-error)
        | append (test-artifacts-collect-main-stack-gone-discovery-unavailable)
        | append (test-artifacts-collect-partial-cache-rerun-backfills)
    ) | flatten
    run-suite "services/platform-up-logs" $SUITE_PATH $results
}
