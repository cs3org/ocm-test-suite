# Compose overlay writer.
# Generates per-execution overlay fragments under /tmp/ocmts/<execution_id>/compose.d/
# and copies them to artifacts/<flow_id>/<pair>/<execution_id>/compose/inputs/ for
# durable access.

use ./topology-two-party.nu [write-two-party-overlays]
use ./topology-one-party.nu [write-one-party-overlays]

export def write-compose-overlays [
    flow_id: string,
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
    sender_version: string = "",
    receiver_version: string = "",
    bundle: record = {},
    --cell-id: string = "",
] {
    let is_two_party = (not ($receiver_platform | is-empty))
    if $is_two_party {
        (write-two-party-overlays
            $flow_id $sender_platform $receiver_platform
            $artifact_name $execution_id
            $image_ref $receiver_image_ref $mitmproxy_image
            $cypress_image $cypress_dev_image
            $mariadb_image $valkey_image
            $spec_entrypoint $browser $record_video
            $root $artifacts_base
            $sender_version $receiver_version
            --cell-id $cell_id)
    } else {
        (write-one-party-overlays
            $flow_id $sender_platform
            $artifact_name $execution_id
            $image_ref $cypress_image $cypress_dev_image
            $mariadb_image $valkey_image
            $spec_entrypoint $browser $record_video
            $root $artifacts_base
            $sender_version $bundle
            --cell-id $cell_id)
    }
}
