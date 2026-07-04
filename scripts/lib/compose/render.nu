# Compose overlay writer.
# Generates per-execution overlay fragments under /tmp/ocmts/<execution_id>/compose.d/
# and copies them to artifacts/<flow_id>/<pair>/<execution_id>/compose/inputs/ for
# durable access.
# Dispatches to topology-specific writers; see compose/ subdirectory for details.

use ./topology-two-party.nu [write-two-party-overlays]
use ./topology-one-party.nu [write-one-party-overlays]

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
    flow_id: string = "",
    sender_version: string = "",
    receiver_version: string = "",
    # Optional per-slot image refs for one-party bundle platforms (e.g. revad, idp).
    bundle: record = {},
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
            $flow_id $sender_version $receiver_version
            --cell-id $cell_id)
    } else {
        (write-one-party-overlays
            $scenario $sender_platform
            $artifact_name $execution_id
            $image_ref $cypress_image $cypress_dev_image
            $mariadb_image $valkey_image
            $spec_entrypoint $browser $record_video
            $root $artifacts_base
            $sender_version $bundle
            --cell-id $cell_id)
    }
}
