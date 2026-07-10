# Top-level image resolvers: wires config loading with precedence logic.

use ./config.nu [load-images-cfg validate-platform-version]
use ./precedence.nu [resolve-image resolve-platform-image]

# Resolve bundle slot refs and role-prefixed compose service labels.
def resolve-bundle-slots [
    bundle_spec: record,
    role: string,
    matrix_key: string,
    flow_id: string,
] {
    if ($bundle_spec | is-empty) {
        return {bundle: {}, bundle_services: {}}
    }
    let bundle = (
        $bundle_spec
        | transpose key val
        | reduce --fold {} {|row, acc|
            let ref = (resolve-image $row.val $matrix_key $flow_id)
            if $ref == null { $acc } else { $acc | upsert $row.key $ref }
        }
    )
    let bundle_services = (
        $bundle
        | columns
        | reduce --fold {} {|slot, acc|
            let slot_spec = ($bundle_spec | get $slot)
            let svc = ($slot_spec.service? | default $slot)
            $acc | upsert $slot $"($role)-($svc)"
        }
    )
    {bundle: $bundle, bundle_services: $bundle_services}
}

# Resolve sender platform images plus shared helper images.
# Returns {platform, bundle, bundle_services, cypress_ci, cypress_dev, mariadb, valkey}.
# bundle maps slot names to resolved refs when ver_spec.bundle is present.
# bundle_services maps slot names to their real compose service name (for evidence),
# defaulting to sender-<slot> when a slot omits an explicit service.
# Pass --matrix-key and --flow-id to enable by_matrix_key/by_flow precedence.
export def resolve-images [
    platform: string,
    version: string,
    --matrix-key: string = "",
    --flow-id: string = "",
] {
    validate-platform-version $platform $version
    let imgs = load-images-cfg
    let plat_spec = ($imgs.platforms | get $platform)
    let ver_spec = ($plat_spec | get $version)
    let bundle_result = (
        resolve-bundle-slots ($ver_spec.bundle? | default {}) "sender" $matrix_key $flow_id
    )
    {
        platform: (resolve-platform-image $ver_spec "sender" $matrix_key $flow_id),
        bundle: $bundle_result.bundle,
        bundle_services: $bundle_result.bundle_services,
        cypress_ci: (resolve-image $imgs.cypress.ci $matrix_key $flow_id),
        cypress_dev: (resolve-image $imgs.cypress.dev $matrix_key $flow_id),
        mariadb: (resolve-image $imgs.helpers.mariadb $matrix_key $flow_id),
        valkey: (resolve-image $imgs.helpers.valkey $matrix_key $flow_id),
    }
}

# Resolve receiver platform image and optional bundle slots for two-party runs.
export def resolve-receiver-images [
    platform: string,
    version: string,
    --matrix-key: string = "",
    --flow-id: string = "",
] {
    validate-platform-version $platform $version
    let imgs = load-images-cfg
    let plat_spec = ($imgs.platforms | get $platform)
    let ver_spec = ($plat_spec | get $version)
    let bundle_result = (
        resolve-bundle-slots ($ver_spec.bundle? | default {}) "receiver" $matrix_key $flow_id
    )
    {
        platform: (resolve-platform-image $ver_spec "receiver" $matrix_key $flow_id),
        bundle: $bundle_result.bundle,
        bundle_services: $bundle_result.bundle_services,
    }
}

# Resolve image ref for a receiver platform/version (platform image only).
# Pass --matrix-key and --flow-id to enable by_matrix_key/by_flow precedence.
export def resolve-receiver-image [
    platform: string,
    version: string,
    --matrix-key: string = "",
    --flow-id: string = "",
] {
    (resolve-receiver-images $platform $version --matrix-key $matrix_key --flow-id $flow_id).platform
}

export def resolve-mitmproxy-image [
    --matrix-key: string = "",
    --flow-id: string = "",
] {
    let imgs = load-images-cfg
    let spec = $imgs.mitmproxy?
    if $spec == null {
        error make {msg: "config/images.nuon missing mitmproxy leaf"}
    }
    resolve-image $spec $matrix_key $flow_id
}

export def resolve-media-optimizer-image [
    --matrix-key: string = "",
    --flow-id: string = "",
] {
    let imgs = load-images-cfg
    let spec = $imgs.helpers.media_optimizer?
    if $spec == null {
        error make {msg: "config/images.nuon missing helpers.media_optimizer leaf"}
    }
    resolve-image $spec $matrix_key $flow_id
}
