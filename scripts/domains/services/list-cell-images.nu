# Print one unique runtime image ref per line for a cell.
# Used by CI pre-pull steps to pull images before running tests.
# Two-party cells: sender platform, receiver platform, mitmproxy, mariadb, valkey, cypress CI.
# One-party cells: sender platform, mariadb, valkey, cypress CI.
# cypress_dev is excluded (not used by headless services up run).

use ../../lib/matrix/cell.nu [validate-cell-rules compute-cell]
use ../../lib/images/resolve.nu [
    resolve-images
    resolve-receiver-image
    resolve-mitmproxy-image
]

def main [
    --scenario: string,
    --sender-platform: string,
    --sender-version: string,
    --receiver-platform: string = "",
    --receiver-version: string = "",
    --browser: string = "chrome",
] {
    let flow_id = (validate-cell-rules
        $scenario $sender_platform $sender_version $browser
        $receiver_platform $receiver_version)
    let is_two_party = (not ($receiver_platform | is-empty))

    let sender_images = (resolve-images $sender_platform $sender_version
        --scenario $scenario --flow-id $flow_id)

    mut refs: list<string> = [
        $sender_images.platform
        $sender_images.cypress_ci
        $sender_images.mariadb
        $sender_images.valkey
    ]

    if $is_two_party {
        let recv_img = (resolve-receiver-image $receiver_platform $receiver_version
            --scenario $scenario --flow-id $flow_id)
        let mitm_img = (resolve-mitmproxy-image --scenario $scenario --flow-id $flow_id)
        $refs = ($refs | append [$recv_img $mitm_img])
    }

    for img in ($refs | uniq) {
        print $img
    }
}
