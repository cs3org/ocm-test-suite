# Shared run context setup: validate, compute cell, create dirs, render overlays,
# write initial metadata.

use ../cell.nu [compute-cell validate-cell-rules assert-scenario-enabled]
use ../images.nu [resolve-images resolve-receiver-image resolve-mitmproxy-image]
use ../execution-id.nu [new-execution-id]
use ../actors.nu [validate-actor-config]
use ../compose-render.nu [write-compose-overlays]
use ../run-metadata.nu [write-prepared-run utc-now]
use ../artifacts-init.nu [init-artifact-dirs write-last-execution-id]
use ../domain/core/ocmts-root.nu [get-ocmts-root]

# Compute IDs, create dirs, generate overlays, write initial metadata.
# Returns the run context record used by services domain commands.
export def setup-run-context [
    scenario: string,
    sender_platform: string,
    sender_version: string,
    browser: string,
    record_video: bool,
    receiver_platform: string = "",
    receiver_version: string = "",
] {
    let root = get-ocmts-root
    assert-scenario-enabled $scenario
    let flow_id = (validate-cell-rules
        $scenario $sender_platform $sender_version $browser
        $receiver_platform $receiver_version)
    (validate-actor-config $scenario $root $sender_platform $receiver_platform)
    let cell = (compute-cell
        $scenario $sender_platform $sender_version $browser
        $receiver_platform $receiver_version $flow_id)
    let images = (resolve-images $sender_platform $sender_version)
    let receiver_image = if $cell.is_two_party {
        resolve-receiver-image $receiver_platform $receiver_version
    } else { "" }
    let mitmproxy_image = if $cell.is_two_party {
        resolve-mitmproxy-image
    } else { "" }

    let execution_id = (new-execution-id)
    let artifacts_base = (init-artifact-dirs $cell.artifact_name $execution_id)

    let spec_entrypoint = $"cypress/e2e/($cell.scenario_module)/index.cy.ts"
    let overlay = (write-compose-overlays
        $scenario $sender_platform
        $cell.artifact_name $execution_id
        $images.platform $images.cypress_ci $images.cypress_dev
        $images.mariadb $images.valkey
        $spec_entrypoint $browser $record_video
        $root $artifacts_base
        $receiver_platform $receiver_image $mitmproxy_image
        $cell.flow_id
        --cell-id $cell.cell_id
    )

    let started_at = (utc-now)

    let images_full = if $cell.is_two_party {
        $images | insert receiver_platform $receiver_image | insert mitmproxy $mitmproxy_image
    } else {
        $images
    }

    ($cell | insert execution_id $execution_id | insert images $images_full)
        | to json
        | save --force ($artifacts_base | path join "meta/cell.json")

    (write-prepared-run
        $artifacts_base $execution_id $cell.cell_id
        $cell.artifact_name $started_at $overlay.stack_id)

    write-last-execution-id $cell.artifact_name $execution_id

    {
        cell: $cell,
        images: $images_full,
        execution_id: $execution_id,
        artifacts_base: $artifacts_base,
        started_at: $started_at,
        stack_id: $overlay.stack_id,
        compose_d: $overlay.compose_d,
        base_yml: $overlay.base_yml,
        base_overlay_fnames: $overlay.base_overlay_fnames,
        is_two_party: $overlay.is_two_party,
        env_file: $overlay.env_file,
    }
}
