# Resolve image refs from config/images.nuon.
# Each leaf is {default, override_env}; env var wins when set and non-empty.

use ./domain/core/ocmts-root.nu [get-ocmts-root]

def resolve-image [spec: record] {
    let env_val = ($env | get --optional $spec.override_env | default "")
    if ($env_val | is-empty) { $spec.default } else { $env_val }
}

def load-images-cfg [] {
    let root = get-ocmts-root
    open ($root | path join "config/images.nuon")
}

# Return all configured platforms and versions as a table.
export def list-platforms-versions [] {
    let imgs = load-images-cfg
    $imgs.platforms | items {|plat, versions|
        $versions | items {|ver, spec|
            {
                platform: $plat,
                version: $ver,
                default_image: $spec.default,
                env_override: $spec.override_env,
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
    let known_versions = ($imgs.platforms | get $platform | columns)
    if not ($version in $known_versions) {
        error make {msg: $"Version '($version)' not known for platform '($platform)'. Known: ($known_versions | str join ', ')"}
    }
}

# Resolve sender platform images plus shared helper images.
# Returns {platform, cypress_ci, cypress_dev, mariadb, valkey}.
export def resolve-images [platform: string, version: string] {
    validate-platform-version $platform $version
    let imgs = load-images-cfg
    {
        platform: (resolve-image ($imgs.platforms | get $platform | get $version)),
        cypress_ci: (resolve-image $imgs.cypress.ci),
        cypress_dev: (resolve-image $imgs.cypress.dev),
        mariadb: (resolve-image $imgs.helpers.mariadb),
        valkey: (resolve-image $imgs.helpers.valkey),
    }
}

# Resolve image ref for a receiver platform/version.
# Errors when the platform or version is not in config/images.nuon.
export def resolve-receiver-image [platform: string, version: string] {
    validate-platform-version $platform $version
    let imgs = load-images-cfg
    resolve-image ($imgs.platforms | get $platform | get $version)
}

# Resolve the mitmproxy image ref from config/images.nuon.
# Errors when the mitmproxy leaf is missing.
export def resolve-mitmproxy-image [] {
    let imgs = load-images-cfg
    let spec = $imgs.mitmproxy?
    if $spec == null {
        error make {msg: "config/images.nuon missing mitmproxy leaf"}
    }
    resolve-image $spec
}
