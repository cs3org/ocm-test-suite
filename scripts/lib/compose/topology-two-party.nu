# Two-party compose overlay writer (e.g. share-with flow with MITM).
# Uses platform cookbooks from config/compose/cookbooks/ and writes a per-run
# stack.env for docker compose variable substitution.

use ./yaml.nu [platform-party-host yaml-env-entry]
use ./topology-common.nu [
    make-stack-context
    write-exec-yml
    copy-platform-cookbook
    copy-overlays-to-artifacts
    ocmgo-env-lines
    party-idp-env
]
use ../actors/load.nu [load-sender-for-tuple load-receiver-for-tuple]
use ../images/resolve.nu [resolve-images resolve-receiver-images]
use ../matrix/cell.nu [tuple-matrix-key validate-browser]
use ../ocm/endpoints.nu [resolve-ocm-provider provider-env-lines]
use ../run/flow-topology.nu [flow-has-sender-hub load-flow-topology]
use ./topology-sender-hub.nu [
    apply-sender-hub-compose-overlays
    sender-hub-base-overlay-fnames
    sender-hub-extend-sender-no-proxy
    sender-hub-runner-depends-on-lines
    sender-hub-sender-trusted-domains
    sender-hub-stack-env-lines
]

# Runner depends_on lines shared by runner-ci.yml and runner-dev.yml.
def two-party-runner-depends-on-lines [flow_id: string, topology: record] {
    mut lines = [
        "      sender:"
        "        condition: service_healthy"
        "      receiver:"
        "        condition: service_healthy"
    ]
    if (flow-has-sender-hub $flow_id $topology) {
        $lines = ($lines | append (sender-hub-runner-depends-on-lines))
    }
    $lines
}

# Same-side compose service names from a platform cookbook (empty when missing).
def cookbook-service-names [root: string, platform: string, role: string] {
    let cookbook_path = ($root | path join "config/compose/cookbooks" $"($platform).($role).yml")
    if not ($cookbook_path | path exists) {
        return []
    }
    try {
        let cooked = (open $cookbook_path)
        if not ("services" in ($cooked | columns)) {
            return []
        }
        $cooked | get services | columns
    } catch {
        []
    }
}

# Write stack.env for a two-party run into art_inputs/.
# Returns the absolute path to the written file.
export def write-two-party-env [
    art_inputs: string,
    sender_platform: string,
    receiver_platform: string,
    sender_version: string,
    receiver_version: string,
    sender_image_ref: string,
    receiver_image_ref: string,
    mariadb_image: string,
    valkey_image: string,
    record_video: bool,
    root: string,
    sender_actor: any,
    receiver_actor: any,
    exec_cidr: string,
    sender_idp_env: record = {},
    receiver_idp_env: record = {},
    sender_bundle: record = {},
    receiver_bundle: record = {},
    flow_id: string = "",
    topology: record = {},
]: nothing -> string {
    let sender_party_host = (platform-party-host $sender_platform 1)
    let receiver_party_host = (platform-party-host $receiver_platform 2)
    let record_str = if $record_video { "true" } else { "false" }
    let sender_short_host = ($sender_party_host | str replace --regex '\.docker$' '')
    let receiver_short_host = ($receiver_party_host | str replace --regex '\.docker$' '')
    let artifacts_base = ($art_inputs | path dirname | path dirname)

    mut sender_no_proxy = [
        "localhost" "127.0.0.1" "mitm"
        "sender" "sender-db" "sender-cache"
        $sender_party_host
    ]
    if not ($sender_idp_env | is-empty) {
        $sender_no_proxy = ($sender_no_proxy | append $sender_idp_env.host)
    }
    $sender_no_proxy = (
        $sender_no_proxy
        | append (cookbook-service-names $root $sender_platform "sender")
        | uniq
    )
    $sender_no_proxy = (
        sender-hub-extend-sender-no-proxy $sender_no_proxy $flow_id $topology $root $sender_platform
    )
    mut receiver_no_proxy = [
        "localhost" "127.0.0.1" "mitm"
        "receiver" "receiver-db" "receiver-cache"
        $receiver_party_host
    ]
    if not ($receiver_idp_env | is-empty) {
        $receiver_no_proxy = ($receiver_no_proxy | append $receiver_idp_env.host)
    }
    $receiver_no_proxy = (
        $receiver_no_proxy
        | append (cookbook-service-names $root $receiver_platform "receiver")
        | uniq
    )
    let sender_no_proxy_str = ($sender_no_proxy | str join ",")
    let receiver_no_proxy_str = ($receiver_no_proxy | str join ",")

    let sender_provider = (resolve-ocm-provider $root $sender_platform 1 $sender_version)
    let receiver_provider = (resolve-ocm-provider $root $receiver_platform 2 $receiver_version)
    let ocm_provider_lines = (provider-env-lines [$sender_provider $receiver_provider])

    let sender_trusted_domains = (
        sender-hub-sender-trusted-domains $sender_party_host $flow_id $topology
    )

    mut lines = [
        $"OCMTS_ROOT=($root)"
        $"OCMTS_ARTIFACTS_BASE=($artifacts_base)"
        $"SENDER_IMAGE=($sender_image_ref)"
        $"RECEIVER_IMAGE=($receiver_image_ref)"
        $"MARIADB_IMAGE=($mariadb_image)"
        $"VALKEY_IMAGE=($valkey_image)"
        $"SENDER_PARTY_HOST=($sender_party_host)"
        "SENDER_MYSQL_HOST=sender-db"
        "SENDER_REDIS_HOST=sender-cache"
        "SENDER_HTTP_PROXY=http://mitm:8080"
        "SENDER_HTTPS_PROXY=http://mitm:8080"
        $"SENDER_NO_PROXY=($sender_no_proxy_str)"
        $"SENDER_PLATFORM=($sender_platform)"
        $"SENDER_PUBLIC_ORIGIN=https://($sender_party_host)"
        $"SENDER_TRUSTED_DOMAINS=($sender_trusted_domains)"
        $"RECEIVER_PARTY_HOST=($receiver_party_host)"
        "RECEIVER_MYSQL_HOST=receiver-db"
        "RECEIVER_REDIS_HOST=receiver-cache"
        "RECEIVER_HTTP_PROXY=http://mitm:8080"
        "RECEIVER_HTTPS_PROXY=http://mitm:8080"
        $"RECEIVER_NO_PROXY=($receiver_no_proxy_str)"
        $"RECEIVER_PLATFORM=($receiver_platform)"
        $"RECEIVER_PUBLIC_ORIGIN=https://($receiver_party_host)"
        $"CYPRESS_baseUrl=https://($sender_party_host)"
        $"CYPRESS_sender_baseUrl=https://($sender_party_host)"
        $"CYPRESS_receiver_baseUrl=https://($receiver_party_host)"
        $"CYPRESS_video=($record_str)"
        "CYPRESS_screenshotsFolder=/artifacts/cypress/screenshots"
        "CYPRESS_videosFolder=/artifacts/cypress/videos"
        "CYPRESS_downloadsFolder=/artifacts/cypress/downloads"
    ]
    if (flow-has-sender-hub $flow_id $topology) {
        $lines = ($lines | append (sender-hub-stack-env-lines $flow_id $topology))
    }
    $lines = ($lines | append (ocmgo-env-lines "sender" $sender_platform $sender_actor $sender_short_host $exec_cidr))
    $lines = ($lines | append (ocmgo-env-lines "receiver" $receiver_platform $receiver_actor $receiver_short_host $exec_cidr))
    if $sender_actor != null {
        $lines = ($lines | append [
            $"CYPRESS_sender_username=($sender_actor.username)"
            $"CYPRESS_sender_password=($sender_actor.password)"
        ])
    }
    if $receiver_actor != null {
        $lines = ($lines | append [
            $"CYPRESS_receiver_username=($receiver_actor.username)"
            $"CYPRESS_receiver_password=($receiver_actor.password)"
        ])
    }
    if not ($sender_idp_env | is-empty) {
        $lines = ($lines | append [
            $"SENDER_IDP_HOST=($sender_idp_env.host)"
            $"SENDER_IDP_ORIGIN=($sender_idp_env.origin)"
            $"CYPRESS_sender_idp_origin=($sender_idp_env.origin)"
            $"CYPRESS_sender_idp_realm=($sender_idp_env.realm)"
        ])
    }
    if not ($receiver_idp_env | is-empty) {
        $lines = ($lines | append [
            $"RECEIVER_IDP_HOST=($receiver_idp_env.host)"
            $"RECEIVER_IDP_ORIGIN=($receiver_idp_env.origin)"
            $"CYPRESS_receiver_idp_origin=($receiver_idp_env.origin)"
            $"CYPRESS_receiver_idp_realm=($receiver_idp_env.realm)"
        ])
    }
    for slot in ($sender_bundle | columns) {
        let slot_up = ($slot | str upcase)
        $lines = ($lines | append $"SENDER_($slot_up)_IMAGE=($sender_bundle | get $slot)")
    }
    for slot in ($receiver_bundle | columns) {
        let slot_up = ($slot | str upcase)
        $lines = ($lines | append $"RECEIVER_($slot_up)_IMAGE=($receiver_bundle | get $slot)")
    }
    $lines = ($lines | append $ocm_provider_lines)

    let env_path = ($art_inputs | path join "stack.env")
    $lines | str join "\n" | save --force $env_path
    $env_path
}

# Write overlays for a two-party flow (e.g. share-with) with MITM.
# Returns {stack_id, compose_d, art_inputs, base_yml, base_overlay_fnames, is_two_party, env_file}.
export def write-two-party-overlays [
    flow_id: string,
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
    sender_version: string = "",
    receiver_version: string = "",
    sender_bundle: record = {},
    receiver_bundle: record = {},
    --cell-id: string = "",
] {
    let topology = (load-flow-topology $root)
    let safe_browser = (validate-browser $browser)
    let sender_actor = (load-sender-for-tuple $flow_id $sender_platform $receiver_platform $root $sender_platform)
    let receiver_actor = (load-receiver-for-tuple $flow_id $sender_platform $receiver_platform $root $receiver_platform)

    let sender_idp_env = (party-idp-env $root $sender_platform 1)
    let receiver_idp_env = (party-idp-env $root $receiver_platform 2)

    let tuple = (tuple-matrix-key $flow_id $sender_platform $receiver_platform)
    let eff_sender_bundle = if ($sender_bundle | is-empty) {
        (resolve-images $sender_platform $sender_version
            --matrix-key $tuple.matrix_key --flow-id $tuple.flow_id).bundle
    } else {
        $sender_bundle
    }
    let eff_receiver_bundle = if ($receiver_bundle | is-empty) {
        (resolve-receiver-images $receiver_platform $receiver_version
            --matrix-key $tuple.matrix_key --flow-id $tuple.flow_id).bundle
    } else {
        $receiver_bundle
    }

    let ctx = (make-stack-context $artifact_name $execution_id $root $artifacts_base)
    let stack_id = $ctx.stack_id
    let exec_cidr = $ctx.exec_cidr
    let compose_d = $ctx.compose_d
    let art_inputs = $ctx.art_inputs
    let base_yml = $ctx.base_yml

    # exec.yml: network name binding with deterministic IPAM subnet
    write-exec-yml $compose_d $stack_id $exec_cidr

    # Copy sender and receiver cookbook YAMLs
    copy-platform-cookbook $root $sender_platform "sender" $compose_d
    copy-platform-cookbook $root $receiver_platform "receiver" $compose_d
    if (flow-has-sender-hub $flow_id $topology) {
        apply-sender-hub-compose-overlays $root $flow_id $topology $sender_platform $compose_d $artifacts_base
    }

    # Write stack.env with all substitution variables
    let env_file = (write-two-party-env
        $art_inputs $sender_platform $receiver_platform
        $sender_version $receiver_version
        $sender_image_ref $receiver_image_ref $mariadb_image $valkey_image
        $record_video $root $sender_actor $receiver_actor $exec_cidr
        $sender_idp_env $receiver_idp_env $eff_sender_bundle $eff_receiver_bundle
        $flow_id $topology)

    let sender_party_host = (platform-party-host $sender_platform 1)
    let receiver_party_host = (platform-party-host $receiver_platform 2)

    # mitm.yml: mitmproxy traffic capture service (still generated; has execution-scoped vars)
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
        $"      - OCMTS_FLOW_ID=($flow_id)"
        $"      - OCMTS_RUN_ID=($execution_id)"
        $"      - OCMTS_EXECUTION_ID=($execution_id)"
        "      - OCMTS_MITM_STARTUP_PATH=/mitm/startup.v1.json"
        "      - OCMTS_MITM_CONNECT_ERRORS_PATH=/mitm/connect-errors.v1.jsonl"
        "    volumes:"
        $"      - ($artifacts_base)/mitm:/mitm"
        $"      - ($root)/scripts/python/lib/mitm/mitmproxy_jsonl.py:/ocmts/mitmproxy_jsonl.py:ro"
    ] | str join "\n") | save --force ($compose_d | path join "mitm.yml")

    # Create MITM artifact placeholder files and confdir with config.yaml.
    mkdir ($artifacts_base | path join "mitm" "flows")
    "" | save --force ($artifacts_base | path join "mitm" "flows" "traffic.jsonl")
    "" | save --force ($artifacts_base | path join "mitm" "flows" "session.json")
    "" | save --force ($artifacts_base | path join "mitm" "redaction-report.json")
    "" | save --force ($artifacts_base | path join "mitm" "startup.v1.json")
    "" | save --force ($artifacts_base | path join "mitm" "connect-errors.v1.jsonl")
    mkdir ($artifacts_base | path join "mitm" "conf")
    "scripts:\n  - /ocmts/mitmproxy_jsonl.py\n"
        | save --force ($artifacts_base | path join "mitm" "conf" "config.yaml")

    let record_str = if $record_video { "true" } else { "false" }

    let runner_depends_on = (two-party-runner-depends-on-lines $flow_id $topology)

    # runner-ci.yml: cypress headless depending on both sender and receiver
    mut runner_ci_lines = [
        "services:"
        "  cypress:"
        $"    image: ($cypress_image)"
        "    depends_on:"
    ]
    $runner_ci_lines = ($runner_ci_lines | append $runner_depends_on | append [
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
    ])
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
    if not ($sender_idp_env | is-empty) {
        $runner_ci_lines = ($runner_ci_lines | append [
            (yaml-env-entry "CYPRESS_sender_idp_origin" $sender_idp_env.origin)
            (yaml-env-entry "CYPRESS_sender_idp_realm" $sender_idp_env.realm)
        ])
    }
    if not ($receiver_idp_env | is-empty) {
        $runner_ci_lines = ($runner_ci_lines | append [
            (yaml-env-entry "CYPRESS_receiver_idp_origin" $receiver_idp_env.origin)
            (yaml-env-entry "CYPRESS_receiver_idp_realm" $receiver_idp_env.realm)
        ])
    }
    if not ($cell_id | is-empty) {
        $runner_ci_lines = ($runner_ci_lines | append [
            $"      - CYPRESS_proof_cell=($cell_id)"
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
    ]
    $runner_dev_lines = ($runner_dev_lines | append $runner_depends_on | append [
        "    shm_size: \"2g\""
        "    ports:"
        "      - \"0:6901\""
        "    networks: [ocm-net]"
        "    working_dir: /workspace"
        "    environment:"
        $"      - CYPRESS_baseUrl=https://($sender_party_host)"
        $"      - CYPRESS_sender_baseUrl=https://($sender_party_host)"
        $"      - CYPRESS_receiver_baseUrl=https://($receiver_party_host)"
    ])
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
    if not ($sender_idp_env | is-empty) {
        $runner_dev_lines = ($runner_dev_lines | append [
            (yaml-env-entry "CYPRESS_sender_idp_origin" $sender_idp_env.origin)
            (yaml-env-entry "CYPRESS_sender_idp_realm" $sender_idp_env.realm)
        ])
    }
    if not ($receiver_idp_env | is-empty) {
        $runner_dev_lines = ($runner_dev_lines | append [
            (yaml-env-entry "CYPRESS_receiver_idp_origin" $receiver_idp_env.origin)
            (yaml-env-entry "CYPRESS_receiver_idp_realm" $receiver_idp_env.realm)
        ])
    }
    if not ($cell_id | is-empty) {
        $runner_dev_lines = ($runner_dev_lines | append [
            $"      - CYPRESS_proof_cell=($cell_id)"
        ])
    }
    $runner_dev_lines = ($runner_dev_lines | append [
        "    volumes:"
        $"      - ($root):/workspace:rw"
        $"      - ($artifacts_base):/artifacts:rw"
    ])
    ($runner_dev_lines | str join "\n") | save --force ($compose_d | path join "runner-dev.yml")

    let base_overlay_fnames = (
        sender-hub-base-overlay-fnames ["exec.yml" "sender.yml" "receiver.yml" "mitm.yml"] $flow_id $topology
    )

    # Copy all overlays to artifacts for durable access.
    copy-overlays-to-artifacts $compose_d $art_inputs $base_overlay_fnames ["runner-ci.yml" "runner-dev.yml"]

    {
        stack_id: $stack_id,
        compose_d: $compose_d,
        art_inputs: $art_inputs,
        base_yml: $base_yml,
        base_overlay_fnames: $base_overlay_fnames,
        is_two_party: true,
        env_file: $env_file,
    }
}
