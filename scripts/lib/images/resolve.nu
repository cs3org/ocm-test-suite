# Top-level image resolvers: wires config loading with precedence logic.

use ./config.nu [load-images-cfg validate-platform-version]
use ./precedence.nu [resolve-image resolve-platform-image]

# Resolve sender platform images plus shared helper images.
# Returns {platform, cypress_ci, cypress_dev, mariadb, valkey}.
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
    {
        platform: (resolve-platform-image $plat_spec $ver_spec "sender" $scenario $flow_id),
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
