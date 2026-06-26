# Top-level image resolvers: wires config loading with precedence logic.

use ./config.nu [load-images-cfg validate-platform-version]
use ./precedence.nu [resolve-image resolve-platform-image]

# Resolve sender platform images plus shared helper images.
# Returns {platform, bundle, bundle_services, cypress_ci, cypress_dev, mariadb, valkey}.
# bundle maps slot names to resolved refs when ver_spec.bundle is present.
# bundle_services maps slot names to their real compose service name (for evidence),
# defaulting to sender-<slot> when a slot omits an explicit service.
# Pass --scenario and --flow-id to enable by_scenario/by_flow precedence.
export def resolve-images [
    platform: string,
    version: string,
    --scenario: string = "",
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
            $acc | upsert $row.key (resolve-image $row.val $scenario $flow_id)
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
        platform: (resolve-platform-image $plat_spec $ver_spec "sender" $scenario $flow_id),
        bundle: $bundle,
        bundle_services: $bundle_services,
        cypress_ci: (resolve-image $imgs.cypress.ci $scenario $flow_id),
        cypress_dev: (resolve-image $imgs.cypress.dev $scenario $flow_id),
        mariadb: (resolve-image $imgs.helpers.mariadb $scenario $flow_id),
        valkey: (resolve-image $imgs.helpers.valkey $scenario $flow_id),
    }
}

# Resolve image ref for a receiver platform/version.
# Pass --scenario and --flow-id to enable by_scenario/by_flow precedence.
export def resolve-receiver-image [
    platform: string,
    version: string,
    --scenario: string = "",
    --flow-id: string = "",
] {
    validate-platform-version $platform $version
    let imgs = load-images-cfg
    let plat_spec = ($imgs.platforms | get $platform)
    let ver_spec = ($plat_spec | get $version)
    resolve-platform-image $plat_spec $ver_spec "receiver" $scenario $flow_id
}

# Resolve the mitmproxy image ref from config/images.nuon.
export def resolve-mitmproxy-image [
    --scenario: string = "",
    --flow-id: string = "",
] {
    let imgs = load-images-cfg
    let spec = $imgs.mitmproxy?
    if $spec == null {
        error make {msg: "config/images.nuon missing mitmproxy leaf"}
    }
    resolve-image $spec $scenario $flow_id
}

# Resolve the media optimizer image ref from config/images.nuon.
export def resolve-media-optimizer-image [
    --scenario: string = "",
    --flow-id: string = "",
] {
    let imgs = load-images-cfg
    let spec = $imgs.helpers.media_optimizer?
    if $spec == null {
        error make {msg: "config/images.nuon missing helpers.media_optimizer leaf"}
    }
    resolve-image $spec $scenario $flow_id
}
