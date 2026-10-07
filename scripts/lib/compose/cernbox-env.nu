# CERNBox Reva registry and federation lines for stack.env.
# Bucket, TTL, and registry timing come from reva-registry-constants.
# Other platforms return an empty list.

use ../services/reva-registry.nu [reva-registry-constants]

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
    let spec = (reva-registry-constants)
    let role_upper = ($role | str uppercase)
    let cidr_json = ([$cidr] | to json --raw)
    [
        $"($role_upper)_REVAD_REGISTRY_DRIVER=nats"
        $"($role_upper)_REVAD_NATS_ADDRESS=nats://($role)-revad-registry:4222"
        $"($role_upper)_REVAD_NATS_BUCKET=($spec.bucket)"
        $"($role_upper)_REVAD_NATS_TTL=($spec.ttl_seconds)s"
        $"($role_upper)_REVAD_REGISTRY_HEARTBEAT_INTERVAL=($spec.heartbeat_interval)"
        $"($role_upper)_REVAD_REGISTRY_DEGRADED_AFTER=($spec.degraded_after)"
        $"($role_upper)_REVAD_REGISTRY_OFFLINE_AFTER=($spec.offline_after)"
        $"($role_upper)_REVAD_REGISTRY_REAP_AFTER=($spec.reap_after)"
        $"($role_upper)_REVAD_ALLOWED_FEDERATION_CIDRS=($cidr_json)"
        $"($role_upper)_REVAD_OCM_TIMEOUT=10"
        $"($role_upper)_REVAD_OCM_CLIENT_INSECURE=true"
        $"($role_upper)_REVAD_OCM_USE_ENV_PROXY=true"
        $"($role_upper)_REVAD_ALLOW_LOOPBACK_FEDERATION=false"
    ]
}
