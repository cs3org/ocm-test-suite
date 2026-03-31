# One-party compose overlay writer (e.g. login scenario).

use ./yaml.nu [
    platform-primary-host platform-party-host
    yaml-env-entry env-lines network-block depends-on-entries
]
use ../actors.nu [load-actor-for-scenario]
use ../cell.nu [validate-browser]
use ../execution-id.nu [execution-temp-path]

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

# Write overlays for a one-party scenario (e.g. login).
# Returns {stack_id, compose_d, art_inputs, base_yml, base_overlay_fnames, is_two_party}.
export def write-one-party-overlays [
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

    # Copy all overlays to artifacts for durable access.
    for fname in ([$base_overlay_fnames ["runner-ci.yml" "runner-dev.yml"]] | flatten) {
        open --raw ($compose_d | path join $fname)
        | save --force ($art_inputs | path join $fname)
    }

    # stack_id.txt: used by `down` and `test run` to reconstruct the compose invocation
    $stack_id | save --force ($artifacts_base | path join "compose" "stack_id.txt")

    # files.txt: base file set; base_yml is the live config path, overlays are artifact input paths
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
