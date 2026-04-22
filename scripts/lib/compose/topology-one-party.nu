# One-party compose overlay writer (e.g. login scenario).
# Uses platform cookbooks from config/compose/cookbooks/ and writes a per-run
# stack.env for docker compose variable substitution.

use ./yaml.nu [platform-party-host yaml-env-entry]
use ./topology-common.nu [
    make-stack-context
    write-exec-yml
    copy-platform-cookbook
    copy-overlays-to-artifacts
    write-stack-id-and-files
    ocmgo-env-lines
]
use ../actors/load.nu [load-actor-for-scenario]
use ../matrix/cell.nu [validate-browser]
use ../ocm/endpoints.nu [resolve-ocm-provider provider-env-lines provider-env-blank-lines]

# Write stack.env for a one-party run into art_inputs/.
# Returns the absolute path to the written file.
def write-one-party-env [
    art_inputs: string,
    platform: string,
    sender_version: string,
    image_ref: string,
    mariadb_image: string,
    valkey_image: string,
    record_video: bool,
    root: string,
    actor: any,
]: nothing -> string {
    let party_host = (platform-party-host $platform 1)
    let record_str = if $record_video { "true" } else { "false" }
    let short_host = ($party_host | str replace --regex '\.docker$' '')
    let artifacts_base = ($art_inputs | path dirname | path dirname)

    let sender_provider = (resolve-ocm-provider $root $platform 1 $sender_version)
    let ocm_provider_lines = (provider-env-lines [$sender_provider])
    # Blank slot 1 so Compose files that reference OCM_PROVIDER_1_* always
    # find a defined (empty) variable rather than an unset-substitution error.
    let ocm_blank_1_lines = (provider-env-blank-lines 1)

    mut lines = [
        $"OCMTS_ROOT=($root)"
        $"OCMTS_ARTIFACTS_BASE=($artifacts_base)"
        $"SENDER_IMAGE=($image_ref)"
        $"MARIADB_IMAGE=($mariadb_image)"
        $"VALKEY_IMAGE=($valkey_image)"
        $"SENDER_PARTY_HOST=($party_host)"
        "SENDER_MYSQL_HOST=sender-db"
        "SENDER_REDIS_HOST=sender-cache"
        "SENDER_HTTP_PROXY="
        "SENDER_HTTPS_PROXY="
        "SENDER_NO_PROXY="
        $"SENDER_PLATFORM=($platform)"
        $"SENDER_PUBLIC_ORIGIN=https://($party_host)"
        "RECEIVER_PARTY_HOST="
        "RECEIVER_PLATFORM="
        "RECEIVER_PUBLIC_ORIGIN="
        $"CYPRESS_baseUrl=https://($party_host)"
        $"CYPRESS_video=($record_str)"
        "CYPRESS_screenshotsFolder=/artifacts/cypress/screenshots"
        "CYPRESS_videosFolder=/artifacts/cypress/videos"
        "CYPRESS_downloadsFolder=/artifacts/cypress/downloads"
    ]
    $lines = ($lines | append (ocmgo-env-lines "sender" $platform $actor $short_host))
    if $actor != null {
        $lines = ($lines | append [
            $"CYPRESS_($actor.platform)_username=($actor.username)"
            $"CYPRESS_($actor.platform)_password=($actor.password)"
        ])
    }
    $lines = ($lines | append $ocm_provider_lines | append $ocm_blank_1_lines)

    let env_path = ($art_inputs | path join "stack.env")
    $lines | str join "\n" | save --force $env_path
    $env_path
}

# Write overlays for a one-party scenario (e.g. login).
# Returns {stack_id, compose_d, art_inputs, base_yml, base_overlay_fnames, is_two_party, env_file}.
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
    sender_version: string = "",
    --cell-id: string = "",
] {
    let safe_browser = (validate-browser $browser)
    let actor = (load-actor-for-scenario $scenario $root $platform)

    let ctx = (make-stack-context $artifact_name $execution_id $root $artifacts_base)
    let stack_id = $ctx.stack_id
    let compose_d = $ctx.compose_d
    let art_inputs = $ctx.art_inputs
    let base_yml = $ctx.base_yml

    # exec.yml: binds the docker-global network name to the stack_id
    write-exec-yml $compose_d $stack_id

    # Copy sender cookbook YAML from config/compose/cookbooks/
    copy-platform-cookbook $root $platform "sender" $compose_d

    # Write stack.env with all substitution variables
    let env_file = (write-one-party-env
        $art_inputs $platform $sender_version $image_ref $mariadb_image $valkey_image
        $record_video $root $actor)

    let party_host = (platform-party-host $platform 1)
    let record_str = if $record_video { "true" } else { "false" }

    # runner-ci.yml: cypress headless runner
    mut runner_ci_lines = [
        "services:"
        "  cypress:"
        $"    image: ($cypress_image)"
        "    depends_on:"
        "      sender:"
        "        condition: service_healthy"
        "    networks: [ocm-net]"
        "    working_dir: /workspace"
        "    environment:"
        $"      - CYPRESS_baseUrl=https://($party_host)"
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

    # runner-dev.yml: cypress_dev kasm desktop workspace
    mut runner_dev_lines = [
        "services:"
        "  cypress_dev:"
        $"    image: ($cypress_dev_image)"
        "    depends_on:"
        "      sender:"
        "        condition: service_healthy"
        "    shm_size: \"2g\""
        "    ports:"
        "      - \"0:6901\""
        "    networks: [ocm-net]"
        "    working_dir: /workspace"
        "    environment:"
        $"      - CYPRESS_baseUrl=https://($party_host)"
    ]
    if $actor != null {
        $runner_dev_lines = ($runner_dev_lines | append [
            (yaml-env-entry $"CYPRESS_($actor.platform)_username" $actor.username)
            (yaml-env-entry $"CYPRESS_($actor.platform)_password" $actor.password)
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

    let base_overlay_fnames = ["exec.yml" "sender.yml"]

    # Copy all overlays to artifacts for durable access.
    copy-overlays-to-artifacts $compose_d $art_inputs $base_overlay_fnames ["runner-ci.yml" "runner-dev.yml"]

    write-stack-id-and-files $artifacts_base $stack_id $base_yml $art_inputs $base_overlay_fnames

    {
        stack_id: $stack_id,
        compose_d: $compose_d,
        art_inputs: $art_inputs,
        base_yml: $base_yml,
        base_overlay_fnames: $base_overlay_fnames,
        is_two_party: false,
        env_file: $env_file,
    }
}
