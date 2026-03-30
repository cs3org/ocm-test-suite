# Compose overlay writer.
# Generates per-execution overlay fragments under /tmp/ocmts/<execution_id>/compose.d/
# and copies them to artifacts/<name>/<execution_id>/compose/inputs/ for durable access.

use ./domain/core/ocmts-root.nu [get-ocmts-root]
use ./actors.nu [load-actor-for-scenario load-sender-for-scenario load-receiver-for-scenario]
use ./cell.nu [validate-browser]
use ./execution-id.nu [execution-temp-path]

# Returns the primary (classy) hostname for a platform: <platform>.docker
def platform-primary-host [platform: string]: nothing -> string {
    $"($platform).docker"
}

# Returns the numbered party hostname: <platform><index>.docker
# Used when TLS cert SANs are numbered (e.g. nextcloud1.docker).
def platform-party-host [platform: string, index: int]: nothing -> string {
    $"($platform)($index).docker"
}

# Returns the base URL for a numbered party: https://<platform><index>.docker
def platform-party-base-url [platform: string, index: int]: nothing -> string {
    $"https://(platform-party-host $platform $index)"
}

# Build a YAML environment list entry indented for a service environment block.
# When the value contains chars unsafe in a YAML plain scalar (e.g. spaces, #),
# the ENTIRE "KEY=VALUE" string is YAML-double-quoted so the YAML parser strips
# the quotes before Docker Compose sees the value.  Quoting only the value part
# would leave literal quote characters in the env var, which is wrong.
def yaml-env-entry [k: string, v: string]: nothing -> string {
    # Safe plain scalar: only chars that cannot form YAML special sequences.
    # Colon is included because `:` alone (without a following space) is safe.
    # Space is excluded so "colon-space" sequences always trigger quoting.
    if ($v | parse --regex '^[A-Za-z0-9_./@:-]+$' | is-empty) {
        let kv = $"($k)=($v)"
        let escaped = ($kv | str replace --all "\\" "\\\\" | str replace --all "\"" "\\\"")
        $"      - \"($escaped)\""
    } else {
        $"      - ($k)=($v)"
    }
}

def env-lines [svc_env: record] {
    $svc_env | items {|k, v| yaml-env-entry $k ($v | into string)}
}

# Build the networks block for a service.
# With aliases: expands to the multi-line form with ocm-net aliases.
# Without aliases: emits the compact inline form.
def network-block [aliases: list<string>]: nothing -> string {
    if ($aliases | is-empty) {
        "    networks: [ocm-net]"
    } else {
        let alias_lines = ($aliases | each {|a| $"          - ($a)"})
        (["    networks:" "      ocm-net:" "        aliases:"] | append $alias_lines | str join "\n")
    }
}

# Build depends_on entries for the one-party "platform" service.
def depends-on-entries [helpers: list<string>] {
    $helpers | each {|h|
        match $h {
            "db" => "      platform-db:\n        condition: service_started",
            "cache" => "      platform-cache:\n        condition: service_healthy",
            _ => "",
        }
    } | where {|e| $e != ""}
}

# Build depends_on entries for a named role (sender or receiver).
def named-depends-on-entries [helpers: list<string>, prefix: string] {
    $helpers | each {|h|
        match $h {
            "db" => $"      ($prefix)-db:\n        condition: service_started",
            "cache" => $"      ($prefix)-cache:\n        condition: service_healthy",
            _ => "",
        }
    } | where {|e| $e != ""}
}

def helpers-services [
    helpers: list<string>,
    mariadb_image: string,
    valkey_image: string,
] {
    if ($helpers | is-empty) { return "services: {}" }
    let blocks = ($helpers | each {|h|
        match $h {
            "db" => ([
                "  platform-db:",
                $"    image: ($mariadb_image)",
                "    networks: [ocm-net]",
                "    environment:",
                "      - MYSQL_ROOT_PASSWORD=rootpassword",
                "      - MYSQL_DATABASE=nextcloud",
                "      - MYSQL_USER=nextcloud",
                "      - MYSQL_PASSWORD=nextcloudpassword",
                "    command: --transaction-isolation=READ-COMMITTED --binlog-format=ROW --innodb-file-per-table=1 --skip-innodb-read-only-compressed",
            ] | str join "\n"),
            "cache" => ([
                "  platform-cache:",
                $"    image: ($valkey_image)",
                "    networks: [ocm-net]",
                "    healthcheck:",
                "      test: [\"CMD\",\"valkey-cli\",\"ping\"]",
                "      interval: 2s",
                "      timeout: 3s",
                "      retries: 30",
                "      start_period: 10s",
            ] | str join "\n"),
            _ => "",
        }
    } | where {|e| $e != ""})
    if ($blocks | is-empty) { return "services: {}" }
    ("services:\n" + ($blocks | str join "\n\n"))
}

# Generate helper service blocks for both sender and receiver roles combined.
def two-party-helpers-services [
    helpers: list<string>,
    mariadb_image: string,
    valkey_image: string,
] {
    if ($helpers | is-empty) { return "services: {}" }
    let blocks = ($helpers | each {|h|
        ["sender" "receiver"] | each {|role|
            match $h {
                "db" => ([
                    $"  ($role)-db:",
                    $"    image: ($mariadb_image)",
                    "    networks: [ocm-net]",
                    "    environment:",
                    "      - MYSQL_ROOT_PASSWORD=rootpassword",
                    "      - MYSQL_DATABASE=nextcloud",
                    "      - MYSQL_USER=nextcloud",
                    "      - MYSQL_PASSWORD=nextcloudpassword",
                    "    command: --transaction-isolation=READ-COMMITTED --binlog-format=ROW --innodb-file-per-table=1 --skip-innodb-read-only-compressed",
                ] | str join "\n"),
                "cache" => ([
                    $"  ($role)-cache:",
                    $"    image: ($valkey_image)",
                    "    networks: [ocm-net]",
                    "    healthcheck:",
                    "      test: [\"CMD\",\"valkey-cli\",\"ping\"]",
                    "      interval: 2s",
                    "      timeout: 3s",
                    "      retries: 30",
                    "      start_period: 10s",
                ] | str join "\n"),
                _ => "",
            }
        }
    } | flatten | where {|e| $e != ""})
    if ($blocks | is-empty) { return "services: {}" }
    ("services:\n" + ($blocks | str join "\n\n"))
}

# Generate a single Nextcloud service block for two-party topology.
def nextcloud-service-block [
    role_name: string,
    platform_name: string,
    image_ref: string,
    hc: record,
    helpers: list<string>,
    network_aliases: list<string>,
    base_env: record,
    role_overrides: record,
    actor: any,
    root: string,
] {
    let test_json = ($hc.test | to json --raw)
    let dep_entries = (named-depends-on-entries $helpers $role_name)
    let merged_env = ($base_env | merge $role_overrides)
    mut lines = [
        $"  ($role_name):",
        $"    image: ($image_ref)",
        $"    hostname: ($role_name)",
        (network-block $network_aliases),
        "    healthcheck:",
        $"      test: ($test_json)",
        $"      interval: ($hc.interval)",
        $"      timeout: ($hc.timeout)",
        $"      retries: ($hc.retries)",
        $"      start_period: ($hc.start_period)",
    ]
    if not ($dep_entries | is-empty) {
        $lines = ($lines | append "    depends_on:" | append $dep_entries)
    }
    $lines = ($lines | append "    environment:" | append (env-lines $merged_env))
    if ($actor != null and $platform_name == "nextcloud") {
        $lines = ($lines | append "      - NEXTCLOUD_SEEDED_USERS_FILE=/ocmts/actors/platforms/nextcloud.nuon")
    }
    if $actor != null {
        $lines = ($lines | append [
            "    volumes:",
            $"      - ($root)/config/actors:/ocmts/actors:ro",
        ])
    }
    $lines | str join "\n"
}

# Write overlays for a one-party scenario (e.g. login).
# Returns {stack_id, compose_d, art_inputs, base_yml, base_overlay_fnames, is_two_party}.
def write-one-party-overlays [
    scenario: string,
    platform: string,
    artifact_name: string,
    execution_id: string,
    image_ref: string,
    cypress_image: string,
    cypress_dev_image: string,
    mariadb_image: string,
    valkey_image: string,
    spec_entrypoint: string,
    browser: string,
    record_video: bool,
    root: string,
    artifacts_base: string,
] {
    let safe_browser = (validate-browser $browser)
    let svc = (open ($root | path join $"config/services/($platform).nuon"))
    let helpers = ($svc.helpers? | default [])

    let known_helpers = ["db" "cache"]
    let unknown_helpers = ($helpers | where {|h| not ($h in $known_helpers)})
    if not ($unknown_helpers | is-empty) {
        error make {msg: $"Unknown helpers in config/services/($platform).nuon: ($unknown_helpers | str join ', '). Known: ($known_helpers | str join ', ')"}
    }

    let actor = (load-actor-for-scenario $scenario $root)

    if ($actor != null and $actor.platform != $platform) {
        error make {msg: $"Actor platform '($actor.platform)' in scenarios/($scenario).nuon does not match sender platform '($platform)'. Fix the scenario actor config."}
    }

    let stack_id = $"ocmts--($artifact_name)--($execution_id)"
    let compose_d = (execution-temp-path $execution_id | path join "compose.d")
    mkdir $compose_d
    let art_inputs = ($artifacts_base | path join "compose" "inputs")
    mkdir $art_inputs
    let base_yml = ($root | path join "config/compose/base.yml")

    # exec.yml: binds the docker-global network name to the stack_id
    (["networks:" "  ocm-net:" $"    name: ($stack_id)"] | str join "\n")
        | save --force ($compose_d | path join "exec.yml")

    # platform.yml: platform service with healthcheck, depends_on, and env
    let hc = $svc.healthcheck
    let test_json = ($hc.test | to json --raw)
    let dep_entries = (depends-on-entries $helpers)
    mut platform_lines = [
        "services:"
        "  platform:"
        $"    image: ($image_ref)"
        "    hostname: platform"
        (network-block [(platform-party-host $platform 1) (platform-primary-host $platform)])
        "    healthcheck:"
        $"      test: ($test_json)"
        $"      interval: ($hc.interval)"
        $"      timeout: ($hc.timeout)"
        $"      retries: ($hc.retries)"
        $"      start_period: ($hc.start_period)"
    ]
    if not ($dep_entries | is-empty) {
        $platform_lines = ($platform_lines | append "    depends_on:" | append $dep_entries)
    }
    let party_host = (platform-party-host $platform 1)
    let platform_env = if $platform == "nextcloud" {
        $svc.env | merge {
            APACHE_SERVER_NAME: $party_host,
            OVERWRITEHOST: $party_host,
            NEXTCLOUD_TRUSTED_DOMAINS: $party_host,
        }
    } else {
        $svc.env
    }
    $platform_lines = ($platform_lines | append "    environment:" | append (env-lines $platform_env))
    if ($actor != null and $platform == "nextcloud") {
        $platform_lines = ($platform_lines | append "      - NEXTCLOUD_SEEDED_USERS_FILE=/ocmts/actors/platforms/nextcloud.nuon")
    }
    if $actor != null {
        $platform_lines = ($platform_lines | append [
            "    volumes:"
            $"      - ($root)/config/actors:/ocmts/actors:ro"
        ])
    }
    ($platform_lines | str join "\n") | save --force ($compose_d | path join "platform.yml")

    # helpers.yml: db / cache helper services
    (helpers-services $helpers $mariadb_image $valkey_image)
        | save --force ($compose_d | path join "helpers.yml")

    # runner-ci.yml: cypress headless runner only (no cypress_dev)
    let record_str = if $record_video { "true" } else { "false" }
    mut runner_ci_lines = [
        "services:"
        "  cypress:"
        $"    image: ($cypress_image)"
        "    depends_on:"
        "      platform:"
        "        condition: service_healthy"
        "    networks: [ocm-net]"
        "    working_dir: /workspace"
        "    environment:"
        $"      - CYPRESS_baseUrl=https://(platform-party-host $platform 1)"
        $"      - CYPRESS_video=($record_str)"
        "      - CYPRESS_screenshotsFolder=/artifacts/cypress/screenshots"
        "      - CYPRESS_videosFolder=/artifacts/cypress/videos"
        "      - CYPRESS_downloadsFolder=/artifacts/cypress/downloads"
    ]
    if $actor != null {
        $runner_ci_lines = ($runner_ci_lines | append [
            (yaml-env-entry $"CYPRESS_($actor.platform)_username" $actor.username)
            (yaml-env-entry $"CYPRESS_($actor.platform)_password" $actor.password)
        ])
    }
    $runner_ci_lines = ($runner_ci_lines | append [
        "    volumes:"
        $"      - ($root):/workspace:rw"
        $"      - ($artifacts_base):/artifacts:rw"
        "    command:"
        "      - cypress"
        "      - run"
        "      - --project"
        "      - /workspace"
        "      - --spec"
        $"      - ($spec_entrypoint)"
        "      - --browser"
        $"      - ($safe_browser)"
    ])
    ($runner_ci_lines | str join "\n") | save --force ($compose_d | path join "runner-ci.yml")

    # runner-dev.yml: cypress_dev kasm desktop workspace only (no cypress headless)
    mut runner_dev_lines = [
        "services:"
        "  cypress_dev:"
        $"    image: ($cypress_dev_image)"
        "    depends_on:"
        "      platform:"
        "        condition: service_healthy"
        "    shm_size: \"2g\""
        "    ports:"
        "      - \"0:6901\""
        "    networks: [ocm-net]"
        "    working_dir: /workspace"
        "    environment:"
        $"      - CYPRESS_baseUrl=https://(platform-party-host $platform 1)"
    ]
    if $actor != null {
        $runner_dev_lines = ($runner_dev_lines | append [
            (yaml-env-entry $"CYPRESS_($actor.platform)_username" $actor.username)
            (yaml-env-entry $"CYPRESS_($actor.platform)_password" $actor.password)
        ])
    }
    $runner_dev_lines = ($runner_dev_lines | append [
        "    volumes:"
        $"      - ($root):/workspace:rw"
        $"      - ($artifacts_base):/artifacts:rw"
    ])
    ($runner_dev_lines | str join "\n") | save --force ($compose_d | path join "runner-dev.yml")

    let base_overlay_fnames = ["exec.yml" "platform.yml" "helpers.yml"]

    # Copy all overlays to artifacts.
    for fname in ([$base_overlay_fnames ["runner-ci.yml" "runner-dev.yml"]] | flatten) {
        open --raw ($compose_d | path join $fname)
        | save --force ($art_inputs | path join $fname)
    }

    # stack_id.txt: used by `down` and `test run` to reconstruct the compose invocation
    $stack_id | save --force ($artifacts_base | path join "compose" "stack_id.txt")

    # files.txt: base file set for compose; base_yml is the live config path,
    # overlays are artifact input paths. Excludes runner overlays.
    ([$base_yml] | append ($base_overlay_fnames | each {|f| $art_inputs | path join $f}))
        | str join "\n" | save --force ($artifacts_base | path join "compose" "files.txt")

    {
        stack_id: $stack_id,
        compose_d: $compose_d,
        art_inputs: $art_inputs,
        base_yml: $base_yml,
        base_overlay_fnames: $base_overlay_fnames,
        is_two_party: false,
    }
}

# Write overlays for a two-party scenario (e.g. share-with) with MITM.
# Returns {stack_id, compose_d, art_inputs, base_yml, base_overlay_fnames, is_two_party}.
def write-two-party-overlays [
    scenario: string,
    sender_platform: string,
    receiver_platform: string,
    artifact_name: string,
    execution_id: string,
    sender_image_ref: string,
    receiver_image_ref: string,
    mitmproxy_image: string,
    cypress_image: string,
    cypress_dev_image: string,
    mariadb_image: string,
    valkey_image: string,
    spec_entrypoint: string,
    browser: string,
    record_video: bool,
    root: string,
    artifacts_base: string,
    --cell-id: string = "",
] {
    let safe_browser = (validate-browser $browser)
    let svc = (open ($root | path join $"config/services/($sender_platform).nuon"))
    let helpers = ($svc.helpers? | default [])

    let known_helpers = ["db" "cache"]
    let unknown_helpers = ($helpers | where {|h| not ($h in $known_helpers)})
    if not ($unknown_helpers | is-empty) {
        error make {msg: $"Unknown helpers in config/services/($sender_platform).nuon: ($unknown_helpers | str join ', '). Known: ($known_helpers | str join ', ')"}
    }

    let sender_actor = (load-sender-for-scenario $scenario $root)
    let receiver_actor = (load-receiver-for-scenario $scenario $root)

    let stack_id = $"ocmts--($artifact_name)--($execution_id)"
    let compose_d = (execution-temp-path $execution_id | path join "compose.d")
    mkdir $compose_d
    let art_inputs = ($artifacts_base | path join "compose" "inputs")
    mkdir $art_inputs
    let base_yml = ($root | path join "config/compose/base.yml")

    # exec.yml: network name binding
    (["networks:" "  ocm-net:" $"    name: ($stack_id)"] | str join "\n")
        | save --force ($compose_d | path join "exec.yml")

    # Role-specific env overrides for sender and receiver.
    # NO_PROXY must not include the remote participant's hostname so that
    # cross-party OCM traffic routes through the MITM proxy.
    # Sender bypasses proxy for its own numbered alias and the primary host;
    # the receiver's numbered alias is intentionally absent so cross-party
    # share-with traffic is captured. Receiver mirrors the same logic.
    let sender_party_host = (platform-party-host $sender_platform 1)
    let sender_primary_host = (platform-primary-host $sender_platform)
    let receiver_party_host = (platform-party-host $receiver_platform 2)
    let sender_no_proxy = $"localhost,127.0.0.1,mitm,sender,sender-db,sender-cache,($sender_party_host),($sender_primary_host)"
    let receiver_no_proxy = $"localhost,127.0.0.1,mitm,receiver,receiver-db,receiver-cache,($receiver_party_host)"
    let sender_overrides = {
        NEXTCLOUD_TRUSTED_DOMAINS: $sender_party_host,
        APACHE_SERVER_NAME: $sender_party_host,
        OVERWRITEHOST: $sender_party_host,
        MYSQL_HOST: "sender-db",
        REDIS_HOST: "sender-cache",
        HTTP_PROXY: "http://mitm:8080",
        HTTPS_PROXY: "http://mitm:8080",
        NO_PROXY: $sender_no_proxy,
    }
    let receiver_overrides = {
        NEXTCLOUD_TRUSTED_DOMAINS: $receiver_party_host,
        APACHE_SERVER_NAME: $receiver_party_host,
        OVERWRITEHOST: $receiver_party_host,
        MYSQL_HOST: "receiver-db",
        REDIS_HOST: "receiver-cache",
        HTTP_PROXY: "http://mitm:8080",
        HTTPS_PROXY: "http://mitm:8080",
        NO_PROXY: $receiver_no_proxy,
    }

    # platform.yml: sender + receiver services
    let hc = $svc.healthcheck
    let sender_block = (nextcloud-service-block
        "sender" $sender_platform $sender_image_ref $hc $helpers
        [$sender_party_host $sender_primary_host]
        $svc.env $sender_overrides $sender_actor $root)
    let receiver_block = (nextcloud-service-block
        "receiver" $receiver_platform $receiver_image_ref $hc $helpers
        [$receiver_party_host]
        $svc.env $receiver_overrides $receiver_actor $root)
    ($"services:\n($sender_block)\n\n($receiver_block)")
        | save --force ($compose_d | path join "platform.yml")

    # helpers.yml: sender-db, sender-cache, receiver-db, receiver-cache
    (two-party-helpers-services $helpers $mariadb_image $valkey_image)
        | save --force ($compose_d | path join "helpers.yml")

    # mitm.yml: mitmproxy traffic capture service.
    # MITMPROXY_CONFDIR points to the per-run conf/ dir where config.yaml
    # lives; mitmproxy reads it automatically so no -s flag is needed in
    # the container command.
    ([
        "services:"
        "  mitm:"
        $"    image: ($mitmproxy_image)"
        "    hostname: mitm"
        "    networks: [ocm-net]"
        "    environment:"
        "      - MITMPROXY_CONFDIR=/mitm/conf"
        "      - OCMTS_MITM_TRAFFIC_PATH=/mitm/flows/traffic.jsonl"
        "      - OCMTS_MITM_SESSION_PATH=/mitm/flows/session.json"
        "      - OCMTS_MITM_REDACTION_REPORT_PATH=/mitm/redaction-report.json"
        $"      - OCMTS_CELL_ID=($cell_id)"
        $"      - OCMTS_FLOW_ID=($scenario)"
        $"      - OCMTS_RUN_ID=($execution_id)"
        $"      - OCMTS_EXECUTION_ID=($execution_id)"
        "    volumes:"
        $"      - ($artifacts_base)/mitm:/mitm"
        $"      - ($root)/scripts/lib/mitmproxy-jsonl.py:/ocmts/mitmproxy-jsonl.py:ro"
    ] | str join "\n") | save --force ($compose_d | path join "mitm.yml")

    # Create MITM artifact placeholder files and the confdir with config.yaml
    # so mitmproxy loads the addon script via confdir rather than a CLI flag.
    mkdir ($artifacts_base | path join "mitm" "flows")
    "" | save --force ($artifacts_base | path join "mitm" "flows" "traffic.jsonl")
    "" | save --force ($artifacts_base | path join "mitm" "flows" "session.json")
    "" | save --force ($artifacts_base | path join "mitm" "redaction-report.json")
    mkdir ($artifacts_base | path join "mitm" "conf")
    "scripts:\n  - /ocmts/mitmproxy-jsonl.py\n"
        | save --force ($artifacts_base | path join "mitm" "conf" "config.yaml")

    # runner-ci.yml: cypress headless depending on both sender and receiver
    let record_str = if $record_video { "true" } else { "false" }
    mut runner_ci_lines = [
        "services:"
        "  cypress:"
        $"    image: ($cypress_image)"
        "    depends_on:"
        "      sender:"
        "        condition: service_healthy"
        "      receiver:"
        "        condition: service_healthy"
        "    networks: [ocm-net]"
        "    working_dir: /workspace"
        "    environment:"
        $"      - CYPRESS_baseUrl=https://($sender_party_host)"
        $"      - CYPRESS_sender_baseUrl=https://($sender_party_host)"
        $"      - CYPRESS_receiver_baseUrl=https://($receiver_party_host)"
        $"      - CYPRESS_video=($record_str)"
        "      - CYPRESS_screenshotsFolder=/artifacts/cypress/screenshots"
        "      - CYPRESS_videosFolder=/artifacts/cypress/videos"
        "      - CYPRESS_downloadsFolder=/artifacts/cypress/downloads"
    ]
    if $sender_actor != null {
        $runner_ci_lines = ($runner_ci_lines | append [
            (yaml-env-entry "CYPRESS_sender_username" $sender_actor.username)
            (yaml-env-entry "CYPRESS_sender_password" $sender_actor.password)
        ])
    }
    if $receiver_actor != null {
        $runner_ci_lines = ($runner_ci_lines | append [
            (yaml-env-entry "CYPRESS_receiver_username" $receiver_actor.username)
            (yaml-env-entry "CYPRESS_receiver_password" $receiver_actor.password)
        ])
    }
    $runner_ci_lines = ($runner_ci_lines | append [
        "    volumes:"
        $"      - ($root):/workspace:rw"
        $"      - ($artifacts_base):/artifacts:rw"
        "    command:"
        "      - cypress"
        "      - run"
        "      - --project"
        "      - /workspace"
        "      - --spec"
        $"      - ($spec_entrypoint)"
        "      - --browser"
        $"      - ($safe_browser)"
    ])
    ($runner_ci_lines | str join "\n") | save --force ($compose_d | path join "runner-ci.yml")

    # runner-dev.yml: cypress_dev kasm desktop depending on sender and receiver
    mut runner_dev_lines = [
        "services:"
        "  cypress_dev:"
        $"    image: ($cypress_dev_image)"
        "    depends_on:"
        "      sender:"
        "        condition: service_healthy"
        "      receiver:"
        "        condition: service_healthy"
        "    shm_size: \"2g\""
        "    ports:"
        "      - \"0:6901\""
        "    networks: [ocm-net]"
        "    working_dir: /workspace"
        "    environment:"
        $"      - CYPRESS_baseUrl=https://($sender_party_host)"
        $"      - CYPRESS_sender_baseUrl=https://($sender_party_host)"
        $"      - CYPRESS_receiver_baseUrl=https://($receiver_party_host)"
    ]
    if $sender_actor != null {
        $runner_dev_lines = ($runner_dev_lines | append [
            (yaml-env-entry "CYPRESS_sender_username" $sender_actor.username)
            (yaml-env-entry "CYPRESS_sender_password" $sender_actor.password)
        ])
    }
    if $receiver_actor != null {
        $runner_dev_lines = ($runner_dev_lines | append [
            (yaml-env-entry "CYPRESS_receiver_username" $receiver_actor.username)
            (yaml-env-entry "CYPRESS_receiver_password" $receiver_actor.password)
        ])
    }
    $runner_dev_lines = ($runner_dev_lines | append [
        "    volumes:"
        $"      - ($root):/workspace:rw"
        $"      - ($artifacts_base):/artifacts:rw"
    ])
    ($runner_dev_lines | str join "\n") | save --force ($compose_d | path join "runner-dev.yml")

    let base_overlay_fnames = ["exec.yml" "platform.yml" "helpers.yml" "mitm.yml"]

    # Copy all overlays to artifacts.
    for fname in ([$base_overlay_fnames ["runner-ci.yml" "runner-dev.yml"]] | flatten) {
        open --raw ($compose_d | path join $fname)
        | save --force ($art_inputs | path join $fname)
    }

    $stack_id | save --force ($artifacts_base | path join "compose" "stack_id.txt")

    # files.txt: base file set including mitm overlay.
    ([$base_yml] | append ($base_overlay_fnames | each {|f| $art_inputs | path join $f}))
        | str join "\n" | save --force ($artifacts_base | path join "compose" "files.txt")

    {
        stack_id: $stack_id,
        compose_d: $compose_d,
        art_inputs: $art_inputs,
        base_yml: $base_yml,
        base_overlay_fnames: $base_overlay_fnames,
        is_two_party: true,
    }
}

# Write all compose overlay fragments for one execution.
# Dispatches to one-party or two-party path based on receiver_platform.
# Returns {stack_id, compose_d, art_inputs, base_yml, base_overlay_fnames, is_two_party}.
export def write-compose-overlays [
    scenario: string,
    sender_platform: string,
    artifact_name: string,
    execution_id: string,
    image_ref: string,
    cypress_image: string,
    cypress_dev_image: string,
    mariadb_image: string,
    valkey_image: string,
    spec_entrypoint: string,
    browser: string,
    record_video: bool,
    root: string,
    artifacts_base: string,
    receiver_platform: string = "",
    receiver_image_ref: string = "",
    mitmproxy_image: string = "",
    --cell-id: string = "",
] {
    let is_two_party = (not ($receiver_platform | is-empty))
    if $is_two_party {
        (write-two-party-overlays
            $scenario $sender_platform $receiver_platform
            $artifact_name $execution_id
            $image_ref $receiver_image_ref $mitmproxy_image
            $cypress_image $cypress_dev_image
            $mariadb_image $valkey_image
            $spec_entrypoint $browser $record_video
            $root $artifacts_base
            --cell-id $cell_id)
    } else {
        (write-one-party-overlays
            $scenario $sender_platform
            $artifact_name $execution_id
            $image_ref $cypress_image $cypress_dev_image
            $mariadb_image $valkey_image
            $spec_entrypoint $browser $record_video
            $root $artifacts_base)
    }
}
