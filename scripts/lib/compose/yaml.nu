# Shared YAML building helpers for compose overlay generation.

# Returns the primary (classy) hostname for a platform: <platform>.docker
export def platform-primary-host [platform: string] {
    $"($platform).docker"
}

# Returns the numbered party hostname: <platform><index>.docker
export def platform-party-host [platform: string, index: int] {
    $"($platform)($index).docker"
}

# Returns the base URL for a numbered party: https://<platform><index>.docker
export def platform-party-base-url [platform: string, index: int] {
    $"https://(platform-party-host $platform $index)"
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

export def env-lines [svc_env: record] {
    $svc_env | items {|k, v| yaml-env-entry $k ($v | into string)}
}

# Build the networks block for a service.
export def network-block [aliases: list<string>] {
    if ($aliases | is-empty) {
        "    networks: [ocm-net]"
    } else {
        let alias_lines = ($aliases | each {|a| $"          - ($a)"})
        (["    networks:" "      ocm-net:" "        aliases:"] | append $alias_lines | str join "\n")
    }
}

# Build depends_on entries for the one-party "platform" service.
export def depends-on-entries [helpers: list<string>] {
    $helpers | each {|h|
        match $h {
            "db" => "      platform-db:\n        condition: service_started",
            "cache" => "      platform-cache:\n        condition: service_healthy",
            _ => "",
        }
    } | where {|e| $e != ""}
}

# Build depends_on entries for a named role (sender or receiver).
export def named-depends-on-entries [helpers: list<string>, prefix: string] {
    $helpers | each {|h|
        match $h {
            "db" => $"      ($prefix)-db:\n        condition: service_started",
            "cache" => $"      ($prefix)-cache:\n        condition: service_healthy",
            _ => "",
        }
    } | where {|e| $e != ""}
}
