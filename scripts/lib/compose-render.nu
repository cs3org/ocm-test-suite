# Compose overlay writer.
# Generates per-execution overlay fragments under /tmp/ocmts/<execution_id>/compose.d/
# and copies them to artifacts/<name>/<execution_id>/compose/inputs/ for durable access.

use ./domain/core/ocmts-root.nu [get-ocmts-root]
use ./actors.nu [load-actor-for-scenario]
use ./cell.nu [validate-browser]
use ./execution-id.nu [execution-temp-path]

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

def depends-on-entries [helpers: list<string>] {
    $helpers | each {|h|
        match $h {
            "db" => "      platform-db:\n        condition: service_started",
            "cache" => "      platform-cache:\n        condition: service_healthy",
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

# Write all compose overlay fragments for one execution.
# Returns {stack_id, compose_d, art_inputs, base_yml}.
export def write-compose-overlays [
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

    # Validate helpers before use; unknown names would be silently skipped otherwise.
    let known_helpers = ["db" "cache"]
    let unknown_helpers = ($helpers | where {|h| not ($h in $known_helpers)})
    if not ($unknown_helpers | is-empty) {
        error make {msg: $"Unknown helpers in config/services/($platform).nuon: ($unknown_helpers | str join ', '). Known: ($known_helpers | str join ', ')"}
    }

    let actor = (load-actor-for-scenario $scenario $root)

    # Actor platform must match sender platform for the current one-platform login path.
    # When multi-platform scenarios are added, remove this check at the call site.
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
        "    networks: [ocm-net]"
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
    $platform_lines = ($platform_lines | append "    environment:" | append (env-lines $svc.env))
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

    # helpers.yml: db / cache helper services driven by nextcloud.nuon helpers list
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
        "      - CYPRESS_baseUrl=http://platform"
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
        "      - CYPRESS_baseUrl=http://platform"
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

    # Copy all overlays to artifacts (test env values copied as-is).
    for fname in ["exec.yml" "platform.yml" "helpers.yml" "runner-ci.yml" "runner-dev.yml"] {
        open --raw ($compose_d | path join $fname)
        | save --force ($art_inputs | path join $fname)
    }

    # stack_id.txt: used by `down` and `test run` to reconstruct the compose invocation
    $stack_id | save --force ($artifacts_base | path join "compose" "stack_id.txt")

    # files.txt: base file set for compose; base_yml is the live config path,
    # overlays are artifact input paths. Excludes runner overlays.
    [$base_yml
     ($art_inputs | path join "exec.yml")
     ($art_inputs | path join "platform.yml")
     ($art_inputs | path join "helpers.yml")
    ] | str join "\n" | save --force ($artifacts_base | path join "compose" "files.txt")

    # Resolved compose captures are done by callers via validate-compose-strict
    # immediately before each mutating command, using the exact file set for that
    # command. This avoids silent swallowing and keeps validation co-located with
    # the mutation it guards.

    {
        stack_id: $stack_id,
        compose_d: $compose_d,
        art_inputs: $art_inputs,
        base_yml: $base_yml,
    }
}
