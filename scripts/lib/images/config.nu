# Image config loading and platform/version catalogue helpers.

use ../domain/core/ocmts-root.nu [get-ocmts-root]

export def load-images-cfg [] {
    let root = get-ocmts-root
    let cfg = open ($root | path join "config/images.nuon")
    let ver = ($cfg.schema_version? | default null)
    if $ver != 3 {
        error make {msg: $"config/images.nuon must carry schema_version: 3 \(found: ($ver | to nuon)\). Update the file or check that you are using the correct config."}
    }
    $cfg
}

# Return all configured platforms and versions as a table. A platform is
# only a namespace of versions, so every column under it is a version key.
export def list-platforms-versions [] {
    let imgs = load-images-cfg
    $imgs.platforms | items {|plat, plat_spec|
        $plat_spec | columns | each {|ver|
            let spec = ($plat_spec | get $ver)
            {
                platform: $plat,
                version: $ver,
                default_image: $spec.default,
                env_override: ($spec.override_env? | default ""),
            }
        }
    } | flatten
}

# Validate platform+version exist in config/images.nuon; readable error on bad input.
export def validate-platform-version [platform: string, version: string] {
    let imgs = load-images-cfg
    let known_platforms = ($imgs.platforms | columns)
    if not ($platform in $known_platforms) {
        error make {msg: $"Platform '($platform)' not in config/images.nuon. Known: ($known_platforms | str join ', ')"}
    }
    let plat_spec = ($imgs.platforms | get $platform)
    let known_versions = ($plat_spec | columns)
    if not ($version in $known_versions) {
        error make {msg: $"Version '($version)' not known for platform '($platform)'. Known: ($known_versions | str join ', ')"}
    }
}
