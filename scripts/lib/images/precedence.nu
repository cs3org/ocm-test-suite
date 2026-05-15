# Pure precedence resolvers for image ref lookups (no I/O, no config loading).
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
export def resolve-image [
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
export def resolve-platform-image [
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
