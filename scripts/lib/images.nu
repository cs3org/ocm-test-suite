# Resolve image refs from config/images.nuon.
#
# Platform leaves may carry a platform-level override_env alongside version
# keys. Precedence for platform images:
#   1. version-specific override_env (when present)
#   2. platform-level override_env (fallback)
#   3. version default tag
#
# Non-platform leaves (cypress, helpers, mitmproxy) keep the old flat
# {default, override_env} shape.

use ./domain/core/ocmts-root.nu [get-ocmts-root]

# Resolve a flat {default, override_env} spec (non-platform leaves).
def resolve-image [spec: record] {
    let env_val = ($env | get --optional $spec.override_env | default "")
    if ($env_val | is-empty) { $spec.default } else { $env_val }
}

# Resolve a platform version using override_env precedence rules.
# platform_spec: the full platform record (may contain override_env + version keys)
# version_spec:  the version sub-record (may omit override_env)
def resolve-platform-image [platform_spec: record, version_spec: record] {
    let override_env = (
        $version_spec.override_env?
        | default ($platform_spec.override_env? | default "")
    )
    if ($override_env | is-empty) {
        $version_spec.default
    } else {
        let env_val = ($env | get --optional $override_env | default "")
        if ($env_val | is-empty) { $version_spec.default } else { $env_val }
    }
}

def load-images-cfg [] {
    let root = get-ocmts-root
    open ($root | path join "config/images.nuon")
}

# Return all configured platforms and versions as a table.
export def list-platforms-versions [] {
    let imgs = load-images-cfg
    $imgs.platforms | items {|plat, plat_spec|
        let version_keys = ($plat_spec | columns | where {|k| $k != "override_env"})
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
    let known_versions = ($plat_spec | columns | where {|k| $k != "override_env"})
    if not ($version in $known_versions) {
        error make {msg: $"Version '($version)' not known for platform '($platform)'. Known: ($known_versions | str join ', ')"}
    }
}

# Resolve sender platform images plus shared helper images.
# Returns {platform, cypress_ci, cypress_dev, mariadb, valkey}.
export def resolve-images [platform: string, version: string] {
    validate-platform-version $platform $version
    let imgs = load-images-cfg
    let plat_spec = ($imgs.platforms | get $platform)
    let ver_spec = ($plat_spec | get $version)
    {
        platform: (resolve-platform-image $plat_spec $ver_spec),
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
    let plat_spec = ($imgs.platforms | get $platform)
    let ver_spec = ($plat_spec | get $version)
    resolve-platform-image $plat_spec $ver_spec
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
