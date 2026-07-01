# Shared YAML building helpers for compose overlay generation.

# Returns the numbered party hostname: <platform><index>.docker
export def platform-party-host [platform: string, index: int] {
    $"($platform)($index).docker"
}

# Returns the numbered IdP party hostname: idp<index>.docker
# (idp image SANs cover idp1.docker..idp4.docker).
export def idp-party-host [index: int] {
    $"idp($index).docker"
}

# Build a YAML environment list entry indented for a service environment block.
# When the value contains chars unsafe in a YAML plain scalar (e.g. spaces, #),
# the ENTIRE "KEY=VALUE" string is YAML-double-quoted so the YAML parser strips
# the quotes before Docker Compose sees the value.
export def yaml-env-entry [k: string, v: string] {
    if ($v | parse --regex '^[A-Za-z0-9_./@:-]+$' | is-empty) {
        let kv = $"($k)=($v)"
        let escaped = ($kv | str replace --all "\\" "\\\\" | str replace --all "\"" "\\\"")
        $"      - \"($escaped)\""
    } else {
        $"      - ($k)=($v)"
    }
}
