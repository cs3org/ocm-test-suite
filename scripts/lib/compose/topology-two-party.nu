# Two-party compose overlay writer (e.g. share-with scenario with MITM).
# Uses platform cookbooks from config/compose/cookbooks/ and writes a per-run
# stack.env for docker compose variable substitution.

use ./yaml.nu [platform-party-host yaml-env-entry]
use ./topology-common.nu [
    make-stack-context
    write-exec-yml
    copy-platform-cookbook
    copy-overlays-to-artifacts
    ocmgo-env-lines
]
use ../actors/load.nu [load-sender-for-scenario load-receiver-for-scenario]
use ../matrix/cell.nu [validate-browser]
use ../ocm/endpoints.nu [resolve-ocm-provider provider-env-lines]

# Write stack.env for a two-party run into art_inputs/.
# Returns the absolute path to the written file.
def write-two-party-env [
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
]: nothing -> string {
    let sender_party_host = (platform-party-host $sender_platform 1)
    let receiver_party_host = (platform-party-host $receiver_platform 2)
    let record_str = if $record_video { "true" } else { "false" }
    let sender_short_host = ($sender_party_host | str replace --regex '\.docker$' '')
    let receiver_short_host = ($receiver_party_host | str replace --regex '\.docker$' '')
    let artifacts_base = ($art_inputs | path dirname | path dirname)

    let sender_no_proxy = (
        [
            "localhost" "127.0.0.1" "mitm"
            "sender" "sender-db" "sender-cache"
            $sender_party_host
        ] | str join ","
    )
    let receiver_no_proxy = (
        [
            "localhost" "127.0.0.1" "mitm"
            "receiver" "receiver-db" "receiver-cache"
            $receiver_party_host
        ] | str join ","
    )

    let sender_provider = (resolve-ocm-provider $root $sender_platform 1 $sender_version)
    let receiver_provider = (resolve-ocm-provider $root $receiver_platform 2 $receiver_version)
    let ocm_provider_lines = (provider-env-lines [$sender_provider $receiver_provider])

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
        $"SENDER_NO_PROXY=($sender_no_proxy)"
        $"SENDER_PLATFORM=($sender_platform)"
        $"SENDER_PUBLIC_ORIGIN=https://($sender_party_host)"
        $"RECEIVER_PARTY_HOST=($receiver_party_host)"
        "RECEIVER_MYSQL_HOST=receiver-db"
        "RECEIVER_REDIS_HOST=receiver-cache"
        "RECEIVER_HTTP_PROXY=http://mitm:8080"
        "RECEIVER_HTTPS_PROXY=http://mitm:8080"
        $"RECEIVER_NO_PROXY=($receiver_no_proxy)"
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
    $lines = ($lines | append (ocmgo-env-lines "sender" $sender_platform $sender_actor $sender_short_host $receiver_party_host))
    $lines = ($lines | append (ocmgo-env-lines "receiver" $receiver_platform $receiver_actor $receiver_short_host $sender_party_host))
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
    $lines = ($lines | append $ocm_provider_lines)

    let env_path = ($art_inputs | path join "stack.env")
    $lines | str join "\n" | save --force $env_path
    $env_path
}

# Write overlays for a two-party scenario (e.g. share-with) with MITM.
# Returns {stack_id, compose_d, art_inputs, base_yml, base_overlay_fnames, is_two_party, env_file}.
export def write-two-party-overlays [
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
    flow_id: string = "",
    sender_version: string = "",
    receiver_version: string = "",
    --cell-id: string = "",
] {
    let safe_browser = (validate-browser $browser)
    let effective_flow_id = if ($flow_id | is-empty) { $scenario } else { $flow_id }
    let sender_actor = (load-sender-for-scenario $scenario $root $sender_platform)
    let receiver_actor = (load-receiver-for-scenario $scenario $root $receiver_platform)

    let ctx = (make-stack-context $artifact_name $execution_id $root $artifacts_base)
    let stack_id = $ctx.stack_id
    let compose_d = $ctx.compose_d
    let art_inputs = $ctx.art_inputs
    let base_yml = $ctx.base_yml

    # exec.yml: network name binding
    write-exec-yml $compose_d $stack_id

    # Copy sender and receiver cookbook YAMLs
    copy-platform-cookbook $root $sender_platform "sender" $compose_d
    copy-platform-cookbook $root $receiver_platform "receiver" $compose_d

    # Write stack.env with all substitution variables
    let env_file = (write-two-party-env
        $art_inputs $sender_platform $receiver_platform
        $sender_version $receiver_version
        $sender_image_ref $receiver_image_ref $mariadb_image $valkey_image
        $record_video $root $sender_actor $receiver_actor)

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
        $"      - OCMTS_FLOW_ID=($effective_flow_id)"
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

    # runner-ci.yml: cypress headless depending on both sender and receiver
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

    let base_overlay_fnames = ["exec.yml" "sender.yml" "receiver.yml" "mitm.yml"]

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
