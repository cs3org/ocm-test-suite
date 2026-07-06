# Print one unique runtime image ref per line for a cell.
# Used by CI pre-pull steps to pull images before running tests.

use ../../lib/matrix/cell.nu [validate-cell-rules compute-cell]
use ../../lib/images/resolve.nu [
    resolve-images
    resolve-receiver-images
    resolve-mitmproxy-image
]

def main [
    --flow: string,
    --sender-platform: string,
    --sender-version: string,
    --receiver-platform: string = "",
    --receiver-version: string = "",
    --browser: string = "chrome",
] {
    validate-cell-rules $flow $sender_platform $sender_version $browser $receiver_platform $receiver_version
    let cell = (compute-cell $flow $sender_platform $sender_version $browser $receiver_platform $receiver_version)
    let is_two_party = $cell.is_two_party

    let sender_images = (resolve-images $sender_platform $sender_version
        --matrix-key $cell.matrix_key --flow-id $cell.flow_id)

    mut refs: list<string> = [
        $sender_images.platform
        $sender_images.cypress_ci
        $sender_images.mariadb
        $sender_images.valkey
    ]

    let bundle = ($sender_images.bundle? | default {})
    if not ($bundle | is-empty) {
        $refs = ($refs | append ($bundle | values))
    }

    if $is_two_party {
        let recv_imgs = (resolve-receiver-images $receiver_platform $receiver_version
            --matrix-key $cell.matrix_key --flow-id $cell.flow_id)
        let mitm_img = (resolve-mitmproxy-image --matrix-key $cell.matrix_key --flow-id $cell.flow_id)
        $refs = ($refs | append [$recv_imgs.platform $mitm_img])
        let recv_bundle = ($recv_imgs.bundle? | default {})
        if not ($recv_bundle | is-empty) {
            $refs = ($refs | append ($recv_bundle | values))
        }
    }

    for img in ($refs | uniq) {
        print $img
    }
}
