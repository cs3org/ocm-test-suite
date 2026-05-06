# Image config loading and platform/version catalogue helpers.

use ../domain/core/ocmts-root.nu [get-ocmts-root]

# Keys at the platform spec level that are not version identifiers.
const PLATFORM_RESERVED_KEYS = [
    "override_env"
    "sender_override_env"
    "receiver_override_env"
]

export def load-images-cfg [] {
    let root = get-ocmts-root
    let cfg = open ($root | path join "config/images.nuon")
    let ver = ($cfg.schema_version? | default null)
    if $ver != 2 {
        error make {msg: $"config/images.nuon must carry schema_version: 2 (found: ($ver | to nuon)). Update the file or check that you are using the correct config."}
    }
    $cfg
}

# Return all configured platforms and versions as a table.
export def list-platforms-versions [] {
    let imgs = load-images-cfg
    $imgs.platforms | items {|plat, plat_spec|
        let version_keys = (
            $plat_spec | columns | where {|k| not ($k in $PLATFORM_RESERVED_KEYS)}
        )
        $version_keys | each {|ver|
            let spec = ($plat_spec | get $ver)
            let effective_env = (
                $spec.override_env?
                | default ($plat_spec.override_env? | default "")
            )
            {
                platform: $plat,
                version: $ver,
                default_image: $spec.default,
                env_override: $effective_env,
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
    let known_versions = (
        $plat_spec | columns | where {|k| not ($k in $PLATFORM_RESERVED_KEYS)}
    )
    if not ($version in $known_versions) {
        error make {msg: $"Version '($version)' not known for platform '($platform)'. Known: ($known_versions | str join ', ')"}
    }
}
