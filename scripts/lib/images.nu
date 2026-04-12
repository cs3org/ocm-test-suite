# Resolve image refs from config/images.nuon (schema v2).
#
# Platform images support by_scenario/by_flow/role-level precedence at the
# version leaf. Non-platform leaves also support scenario/flow overrides.
#
# Platform image precedence (11 levels, role = sender or receiver):
#   1.  by_scenario[scenario].<role>_override_env -> env lookup
#   2.  by_flow[flow_id].<role>_override_env      -> env lookup
#   3.  version <role>_override_env               -> env lookup
#   4.  platform <role>_override_env              -> env lookup
#   5.  by_scenario[scenario].override_env        -> env lookup
#   6.  by_flow[flow_id].override_env             -> env lookup
#   7.  version override_env                      -> env lookup
#   8.  platform override_env                     -> env lookup
#   9.  by_scenario[scenario].default
#   10. by_flow[flow_id].default
#   11. version default

use ./domain/core/ocmts-root.nu [get-ocmts-root]

# Keys at the platform spec level that are not version identifiers.
const PLATFORM_RESERVED_KEYS = [
    "override_env"
    "sender_override_env"
    "receiver_override_env"
]

# Attempt an env lookup. Returns the env value when non-empty; null otherwise.
def try-env-override [env_key: any] {
    let k = ($env_key | default "" | into string)
    if ($k | is-empty) { return null }
    let val = ($env | get --optional $k | default "")
    if ($val | is-empty) { null } else { $val }
}

# Resolve a non-platform leaf using the 6-level precedence:
#   1. by_scenario[scenario].override_env -> env lookup
#   2. by_flow[flow_id].override_env      -> env lookup
#   3. leaf override_env                  -> env lookup
#   4. by_scenario[scenario].default
#   5. by_flow[flow_id].default
#   6. leaf default
def resolve-image [
    spec: record,
    scenario: string = "",
    flow_id: string = "",
] {
    let by_scenario_map = ($spec.by_scenario? | default {})
    let by_flow_map = ($spec.by_flow? | default {})
    let sc_spec = if (not ($scenario | is-empty)) {
        $by_scenario_map | get --optional $scenario | default null
    } else { null }
    let fid_spec = if (not ($flow_id | is-empty)) {
        $by_flow_map | get --optional $flow_id | default null
    } else { null }

    let candidates = [
        (if $sc_spec != null {
            try-env-override ($sc_spec | get --optional "override_env" | default null)
        } else { null })
        (if $fid_spec != null {
            try-env-override ($fid_spec | get --optional "override_env" | default null)
        } else { null })
        (try-env-override ($spec | get --optional "override_env" | default null))
        (if $sc_spec != null {
            $sc_spec | get --optional "default" | default null
        } else { null })
        (if $fid_spec != null {
            $fid_spec | get --optional "default" | default null
        } else { null })
        $spec.default
    ]
    $candidates | where {|x| $x != null} | first
}

# Resolve a platform version for role (sender/receiver) using the 11-level
# precedence. scenario and flow_id are optional context; pass "" to skip.
def resolve-platform-image [
    platform_spec: record,
    version_spec: record,
    role: string,
    scenario: string = "",
    flow_id: string = "",
] {
    let role_env_key = $"($role)_override_env"
    let by_scenario_map = ($version_spec.by_scenario? | default {})
    let by_flow_map = ($version_spec.by_flow? | default {})
    let sc_spec = if (not ($scenario | is-empty)) {
        $by_scenario_map | get --optional $scenario | default null
    } else { null }
    let fid_spec = if (not ($flow_id | is-empty)) {
        $by_flow_map | get --optional $flow_id | default null
    } else { null }

    let candidates = [
        # 1. by_scenario[scenario].<role>_override_env
        (if $sc_spec != null {
            try-env-override ($sc_spec | get --optional $role_env_key | default null)
        } else { null })
        # 2. by_flow[flow_id].<role>_override_env
        (if $fid_spec != null {
            try-env-override ($fid_spec | get --optional $role_env_key | default null)
        } else { null })
        # 3. version <role>_override_env
        (try-env-override ($version_spec | get --optional $role_env_key | default null))
        # 4. platform <role>_override_env
        (try-env-override ($platform_spec | get --optional $role_env_key | default null))
        # 5. by_scenario[scenario].override_env
        (if $sc_spec != null {
            try-env-override ($sc_spec | get --optional "override_env" | default null)
        } else { null })
        # 6. by_flow[flow_id].override_env
        (if $fid_spec != null {
            try-env-override ($fid_spec | get --optional "override_env" | default null)
        } else { null })
        # 7. version override_env
        (try-env-override ($version_spec | get --optional "override_env" | default null))
        # 8. platform override_env
        (try-env-override ($platform_spec | get --optional "override_env" | default null))
        # 9. by_scenario[scenario].default
        (if $sc_spec != null {
            $sc_spec | get --optional "default" | default null
        } else { null })
        # 10. by_flow[flow_id].default
        (if $fid_spec != null {
            $fid_spec | get --optional "default" | default null
        } else { null })
        # 11. version default (always present in well-formed config)
        $version_spec.default
    ]
    $candidates | where {|x| $x != null} | first
}

def load-images-cfg [] {
    let root = get-ocmts-root
    open ($root | path join "config/images.nuon")
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
