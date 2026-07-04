# Pure precedence resolvers for image ref lookups (no I/O, no config loading).
#
# Precedence is scope-first: narrower scope wins entirely before a broader
# scope is even considered. Within the winning scope, a role-specific env
# override beats a shared env override, which beats the configured default.
#
# Generic leaf precedence (single-image platform main image, bundle slot,
# or a cypress/helpers/mitmproxy leaf) -- 6 levels:
#   1. by_matrix_key[matrix_key].override_env
#   2. by_matrix_key[matrix_key].default
#   3. by_flow[flow_id].override_env
#   4. by_flow[flow_id].default
#   5. leaf.override_env
#   6. leaf.default
#
# Two-party platform precedence (role = sender or receiver) -- 9 levels:
#   1. by_matrix_key[matrix_key].<role>_override_env
#   2. by_matrix_key[matrix_key].override_env
#   3. by_matrix_key[matrix_key].default
#   4. by_flow[flow_id].<role>_override_env
#   5. by_flow[flow_id].override_env
#   6. by_flow[flow_id].default
#   7. version.<role>_override_env
#   8. version.override_env
#   9. version.default
#
# There is no platform-root tier: the platform object is only a namespace
# of versions.

# Attempt an env lookup. Returns the env value when non-empty; null otherwise.
def try-env-override [env_key: any] {
    let k = ($env_key | default "" | into string)
    if ($k | is-empty) { return null }
    let val = ($env | get --optional $k | default "")
    if ($val | is-empty) { null } else { $val }
}

def first-non-null [candidates: list] {
    let found = ($candidates | where {|x| $x != null})
    if ($found | is-empty) { null } else { $found | first }
}

# Resolve one scope's generic tier: override_env, then default.
def resolve-scope [spec: any] {
    if $spec == null { return null }
    let env_val = (try-env-override ($spec | get --optional "override_env" | default null))
    if $env_val != null { return $env_val }
    $spec | get --optional "default" | default null
}

# Resolve one scope's role-aware tier: role env, then that scope's generic tier.
def resolve-scope-for-role [spec: any, role_env_key: string] {
    if $spec == null { return null }
    let role_val = (try-env-override ($spec | get --optional $role_env_key | default null))
    if $role_val != null { return $role_val }
    resolve-scope $spec
}

# Resolve a generic leaf (single-image platform version, bundle slot, or
# cypress/helpers/mitmproxy leaf) using the 6-level scope-first precedence.
export def resolve-image [
    spec: record,
    matrix_key: string = "",
    flow_id: string = "",
] {
    let matrix_spec = if (not ($matrix_key | is-empty)) {
        ($spec.by_matrix_key? | default {}) | get --optional $matrix_key | default null
    } else { null }
    let fid_spec = if (not ($flow_id | is-empty)) {
        ($spec.by_flow? | default {}) | get --optional $flow_id | default null
    } else { null }

    first-non-null [
        (resolve-scope $matrix_spec)
        (resolve-scope $fid_spec)
        (resolve-scope $spec)
    ]
}

# Resolve a two-party platform version for role (sender/receiver) using the
# 9-level scope-first precedence. matrix_key/flow_id are optional context;
# pass "" to skip that scope.
export def resolve-platform-image [
    version_spec: record,
    role: string,
    matrix_key: string = "",
    flow_id: string = "",
] {
    let role_env_key = $"($role)_override_env"
    let matrix_spec = if (not ($matrix_key | is-empty)) {
        ($version_spec.by_matrix_key? | default {}) | get --optional $matrix_key | default null
    } else { null }
    let fid_spec = if (not ($flow_id | is-empty)) {
        ($version_spec.by_flow? | default {}) | get --optional $flow_id | default null
    } else { null }

    first-non-null [
        (resolve-scope-for-role $matrix_spec $role_env_key)
        (resolve-scope-for-role $fid_spec $role_env_key)
        (resolve-scope-for-role $version_spec $role_env_key)
    ]
}
