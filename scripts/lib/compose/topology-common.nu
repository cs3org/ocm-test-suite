# Shared helpers for one-party and two-party compose topology writers.

use ../run/execution-id.nu [execution-temp-path]

# Build per-run filesystem context and create required directories.
# Returns {stack_id, compose_d, art_inputs, base_yml}.
export def make-stack-context [
    artifact_name: string,
    execution_id: string,
    root: string,
    artifacts_base: string,
]: nothing -> record {
    let stack_id = $"ocmts--($artifact_name)--($execution_id)"
    let compose_d = (execution-temp-path $execution_id | path join "compose.d")
    let art_inputs = ($artifacts_base | path join "compose" "inputs")
    let base_yml = ($root | path join "config/compose/base.yml")
    mkdir $compose_d
    mkdir $art_inputs
    {
        stack_id: $stack_id,
        compose_d: $compose_d,
        art_inputs: $art_inputs,
        base_yml: $base_yml,
    }
}

# Write exec.yml binding the docker-global network name to the stack_id.
export def write-exec-yml [
    compose_d: string,
    stack_id: string,
] {
    (["networks:" "  ocm-net:" $"    name: ($stack_id)"] | str join "\n")
        | save --force ($compose_d | path join "exec.yml")
}

# Copy a platform cookbook YAML into compose_d/<role>.yml.
export def copy-platform-cookbook [
    root: string,
    platform: string,
    role: string,
    compose_d: string,
] {
    let cookbook_src = ($root | path join "config/compose/cookbooks" $"($platform).($role).yml")
    if not ($cookbook_src | path exists) {
        error make {msg: $"No ($role) cookbook for platform '($platform)': config/compose/cookbooks/($platform).($role).yml not found"}
    }
    open --raw $cookbook_src | save --force ($compose_d | path join $"($role).yml")
}

# Copy overlay and runner files from compose_d to art_inputs.
export def copy-overlays-to-artifacts [
    compose_d: string,
    art_inputs: string,
    base_overlay_fnames: list<string>,
    runner_fnames: list<string>,
] {
    for fname in ([$base_overlay_fnames $runner_fnames] | flatten) {
        open --raw ($compose_d | path join $fname)
        | save --force ($art_inputs | path join $fname)
    }
}

# Write stack_id.txt and files.txt under <artifacts_base>/compose/.
export def write-stack-id-and-files [
    artifacts_base: string,
    stack_id: string,
    base_yml: string,
    art_inputs: string,
    base_overlay_fnames: list<string>,
] {
    $stack_id | save --force ($artifacts_base | path join "compose" "stack_id.txt")
    ([$base_yml] | append ($base_overlay_fnames | each {|f| $art_inputs | path join $f}))
        | str join "\n" | save --force ($artifacts_base | path join "compose" "files.txt")
}

# Return OCM_GO_<ROLE_UPPER>_* env lines for ocmgo platforms.
# For non-ocmgo platforms returns blank slot lines.
export def ocmgo-env-lines [
    role: string,
    platform: string,
    actor: any,
    short_host: string,
]: nothing -> list<string> {
    let role_upper = ($role | str upcase)
    if $platform == "ocmgo" {
        if $actor == null {
            error make {msg: $"($role) platform 'ocmgo' requires a ($role) actor (admin credentials); none configured for this scenario"}
        }
        [
            $"OCM_GO_($role_upper)_HOST=($short_host)"
            $"OCM_GO_($role_upper)_ADMIN_USER=($actor.username)"
            $"OCM_GO_($role_upper)_ADMIN_PASSWORD=($actor.password)"
        ]
    } else {
        [
            $"OCM_GO_($role_upper)_HOST="
            $"OCM_GO_($role_upper)_ADMIN_USER="
            $"OCM_GO_($role_upper)_ADMIN_PASSWORD="
        ]
    }
}
