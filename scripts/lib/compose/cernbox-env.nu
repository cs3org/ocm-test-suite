# CERNBox Reva registry and federation lines for stack.env.
# Other platforms return an empty list.

export def cernbox-reva-env-lines [
    role: string,
    platform: string,
    exec_cidr: string,
]: nothing -> list<string> {
    if $platform != "cernbox" {
        return []
    }
    if not ($role in ["sender" "receiver"]) {
        error make {msg: "cernbox reva env requires role sender or receiver"}
    }
    let cidr = ($exec_cidr | str trim)
    if ($cidr | is-empty) {
        error make {msg: "cernbox reva env requires a non-blank allocated CIDR"}
    }
    let role_upper = ($role | str uppercase)
    let cidr_json = ([$cidr] | to json --raw)
    [
        $"($role_upper)_REVAD_REGISTRY_DRIVER=nats"
        $"($role_upper)_REVAD_NATS_ADDRESS=nats://($role)-revad-registry:4222"
        $"($role_upper)_REVAD_NATS_BUCKET=reva_registry"
        $"($role_upper)_REVAD_NATS_TTL=30s"
        $"($role_upper)_REVAD_REGISTRY_HEARTBEAT_INTERVAL=5s"
        $"($role_upper)_REVAD_REGISTRY_DEGRADED_AFTER=15s"
        $"($role_upper)_REVAD_REGISTRY_OFFLINE_AFTER=30s"
        $"($role_upper)_REVAD_REGISTRY_REAP_AFTER=5m"
        $"($role_upper)_REVAD_ALLOWED_FEDERATION_CIDRS=($cidr_json)"
        $"($role_upper)_REVAD_OCM_TIMEOUT=10"
        $"($role_upper)_REVAD_OCM_CLIENT_INSECURE=true"
        $"($role_upper)_REVAD_OCM_USE_ENV_PROXY=false"
        $"($role_upper)_REVAD_ALLOW_LOOPBACK_FEDERATION=false"
    ]
}
