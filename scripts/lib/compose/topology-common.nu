# Shared helpers for one-party and two-party compose topology writers.

use ../run/execution-id.nu [execution-temp-path validate-execution-id]
use ./yaml.nu [idp-party-host]
use ../ocm/endpoints.nu [platform-login-mechanism]

# IdP origin for a party, driven by the platforms.nuon login SSOT.
# Returns "" for same-origin platforms; https://idp<party>.docker for external-idp.
export def party-idp-origin [root: string, platform: string, party: int]: nothing -> string {
    if (platform-login-mechanism $root $platform) == "external-idp" {
        $"https://(idp-party-host $party)"
    } else {
        ""
    }
}

# Derive a deterministic /24 private subnet from execution_id for the
# ocm-net compose network. The execution_id must satisfy the contract
# enforced by validate-execution-id (regex: \d{8}t\d{6}-[0-9a-f]{8}):
# exactly 15-char timestamp prefix (YYYYMMDDtHHMMSS), a dash, then
# exactly 8 lowercase hex chars. Uppercase hex is rejected.
# The tail is always at chars 16-23; first pair (16-17) -> octet B,
# second pair (18-19) -> octet C; result is 10.<B>.<C>.0/24.
# Example: 20260523t194026-c5e486b4 -> tail c5e486b4 -> 10.197.228.0/24.
#
# Hex conversion: prefix each pair with "1" to form a 3-char hex string,
# parse as hex, subtract 256. "0b" -> "10b"=267-256=11. This prevents
# Nushell from treating "0b"/"0x" prefixes as binary/hex literal markers
# even when --radix 16 is explicit.
export def execution-cidr [execution_id: string]: nothing -> string {
    let safe_id = (validate-execution-id $execution_id)
    # Validated format guarantees tail is always at this exact offset.
    let tail = ($safe_id | str substring 16..23)
    let b_hex = ($tail | str substring 0..1)
    let c_hex = ($tail | str substring 2..3)
    let b = (("1" + $b_hex) | into int --radix 16) - 256
    let c = (("1" + $c_hex) | into int --radix 16) - 256
    $"10.($b).($c).0/24"
}

# Build per-run filesystem context and create required directories.
# Returns {stack_id, exec_cidr, compose_d, art_inputs, base_yml}.
export def make-stack-context [
    artifact_name: string,
    execution_id: string,
    root: string,
    artifacts_base: string,
]: nothing -> record {
    let stack_id = $"ocmts--($artifact_name)--($execution_id)"
    let exec_cidr = (execution-cidr $execution_id)
    let compose_d = (execution-temp-path $execution_id | path join "compose.d")
    let art_inputs = ($artifacts_base | path join "compose" "inputs")
    let base_yml = ($root | path join "config/compose/base.yml")
    mkdir $compose_d
    mkdir $art_inputs
    {
        stack_id: $stack_id,
        exec_cidr: $exec_cidr,
        compose_d: $compose_d,
        art_inputs: $art_inputs,
        base_yml: $base_yml,
    }
}

# Write exec.yml binding the docker-global network name to the stack_id
# and configuring IPAM with the deterministic execution CIDR.
export def write-exec-yml [
    compose_d: string,
    stack_id: string,
    exec_cidr: string,
] {
    ([
        "networks:"
        "  ocm-net:"
        $"    name: ($stack_id)"
        "    ipam:"
        "      config:"
        $"        - subnet: ($exec_cidr)"
    ] | str join "\n")
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

# Return OCM_GO_<ROLE_UPPER>_* env lines for ocmgo platforms.
# For non-ocmgo platforms returns blank slot lines.
# exec_cidr is the two-party route gate: pass the execution CIDR for
# two-party runs to emit ROUTE_SUFFIXES and ROUTE_PRIVATE_CIDRS; omit it
# (default null) for one-party or non-ocmgo callers to emit blank slots.
export def ocmgo-env-lines [
    role: string,
    platform: string,
    actor: any,
    short_host: string,
    exec_cidr: any = null,
]: nothing -> list<string> {
    let role_upper = ($role | str upcase)
    let route_lines = if ($platform == "ocmgo" and $exec_cidr != null) {
        let cidr_empty = (($exec_cidr | into string | str trim | str length) == 0)
        if $cidr_empty {
            error make {
                msg: $"ocmgo role '($role)': exec_cidr must be a non-empty CIDR when provided \(got empty string\)"
            }
        }
        [
            $"OCM_GO_($role_upper)_ROUTE_SUFFIXES=.docker"
            $"OCM_GO_($role_upper)_ROUTE_PRIVATE_CIDRS=($exec_cidr)"
        ]
    } else {
        [
            $"OCM_GO_($role_upper)_ROUTE_SUFFIXES="
            $"OCM_GO_($role_upper)_ROUTE_PRIVATE_CIDRS="
        ]
    }
    if $platform == "ocmgo" {
        if $actor == null {
            error make {msg: $"($role) platform 'ocmgo' requires a ($role) actor \(admin credentials\); none configured for this tuple"}
        }
        [
            $"OCM_GO_($role_upper)_HOST=($short_host)"
            $"OCM_GO_($role_upper)_ADMIN_USER=($actor.username)"
            $"OCM_GO_($role_upper)_ADMIN_PASSWORD=($actor.password)"
        ] | append $route_lines
    } else {
        [
            $"OCM_GO_($role_upper)_HOST="
            $"OCM_GO_($role_upper)_ADMIN_USER="
            $"OCM_GO_($role_upper)_ADMIN_PASSWORD="
        ] | append $route_lines
    }
}
