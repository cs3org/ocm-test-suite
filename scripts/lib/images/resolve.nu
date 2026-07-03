# Top-level image resolvers: wires config loading with precedence logic.

use ./config.nu [load-images-cfg validate-platform-version]
use ./precedence.nu [resolve-image resolve-platform-image]

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
    let bundle_spec = ($ver_spec.bundle? | default {})
    let bundle = if ($bundle_spec | is-empty) {
        {}
    } else {
        $bundle_spec
        | transpose key val
        | reduce --fold {} {|row, acc|
            $acc | upsert $row.key (resolve-image $row.val $matrix_key $flow_id)
        }
    }
    let bundle_services = if ($bundle_spec | is-empty) {
        {}
    } else {
        $bundle_spec
        | transpose key val
        | reduce --fold {} {|row, acc|
            $acc | upsert $row.key ($row.val.service? | default $"sender-($row.key)")
        }
    }
    {
        platform: (resolve-platform-image $ver_spec "sender" $matrix_key $flow_id),
        bundle: $bundle,
        bundle_services: $bundle_services,
        cypress_ci: (resolve-image $imgs.cypress.ci $matrix_key $flow_id),
        cypress_dev: (resolve-image $imgs.cypress.dev $matrix_key $flow_id),
        mariadb: (resolve-image $imgs.helpers.mariadb $matrix_key $flow_id),
        valkey: (resolve-image $imgs.helpers.valkey $matrix_key $flow_id),
    }
}

# Resolve image ref for a receiver platform/version.
# Pass --matrix-key and --flow-id to enable by_matrix_key/by_flow precedence.
export def resolve-receiver-image [
    platform: string,
    version: string,
    --matrix-key: string = "",
    --flow-id: string = "",
] {
    validate-platform-version $platform $version
    let imgs = load-images-cfg
    let plat_spec = ($imgs.platforms | get $platform)
    let ver_spec = ($plat_spec | get $version)
    resolve-platform-image $ver_spec "receiver" $matrix_key $flow_id
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
