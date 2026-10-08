# Resolve container endpoints from Docker labels and write mitm/peers.json.

use ../domain/core/ocmts-root.nu [get-ocmts-root]
use ../compose/topology-two-party.nu [cookbook-service-names]
use ../compose/topology-sender-hub.nu [sender-hub-cookbook-service-names]
use ../run/flow-topology.nu [load-flow-topology]

# Parse SENDER_*/RECEIVER_* proxy keys from a stack.env file.
# Returns a proxy record with empty strings for any absent key; never errors.
def read-stack-env-proxy [stack_env_path: string] {
    let target_keys = [
        "SENDER_HTTP_PROXY" "SENDER_HTTPS_PROXY" "SENDER_NO_PROXY"
        "RECEIVER_HTTP_PROXY" "RECEIVER_HTTPS_PROXY" "RECEIVER_NO_PROXY"
    ]
    let rows = if ($stack_env_path | path exists) {
        (
            try { open --raw $stack_env_path | lines } catch { [] }
            | where {|l|
                let t = ($l | str trim)
                (not ($t | is-empty)) and (not ($t | str starts-with "#")) and ($t | str contains "=")
            }
            | each {|l|
                let parts = ($l | str trim | split row "=")
                {key: ($parts | first | str trim), val: ($parts | skip 1 | str join "=")}
            }
            | where {|r| $r.key in $target_keys}
        )
    } else {
        []
    }
    let m = ($rows | reduce --fold {} {|row, acc| $acc | upsert $row.key $row.val})
    {
        sender: {
            http: ($m.SENDER_HTTP_PROXY? | default ""),
            https: ($m.SENDER_HTTPS_PROXY? | default ""),
            no_proxy: ($m.SENDER_NO_PROXY? | default ""),
        },
        receiver: {
            http: ($m.RECEIVER_HTTP_PROXY? | default ""),
            https: ($m.RECEIVER_HTTPS_PROXY? | default ""),
            no_proxy: ($m.RECEIVER_NO_PROXY? | default ""),
        },
        mitm_service: "mitm:8080",
    }
}

# Pure projection of one inspected service on the current run's network.
export def endpoint-from-inspect [stack_id: string, service: string, inspected: record] {
    let net = (try { $inspected.NetworkSettings.Networks | get $stack_id } catch { null })
    if $net == null { return null }
    let ipv4 = ($net.IPAddress? | default "")
    if ($ipv4 | is-empty) { return null }
    let aliases = (
        ($net.Aliases? | default [])
        | append ($net.DNSNames? | default [])
        | where {|host| ($host | describe) == "string" and not ($host | is-empty)}
        | each {|host| $host | str downcase}
        | uniq
    )
    let public_hosts = ($aliases | where {|host| $host | str ends-with ".docker"} | sort)
    let hosts = (
        $public_hosts
        | append [$service ($inspected.Config.Hostname? | default "")]
        | append $aliases
        | where {|host| not ($host | is-empty)}
        | uniq
    )
    {service: $service, ipv4: $ipv4, hosts: $hosts}
}

# Primary/hub services always participate; auxiliaries need this run's proxy.
export def endpoint-is-participant [service: string, hub_services: list<string>, env_lines: list<string>, proxy: record] {
    if $service in ["sender" "receiver" "mitm"] or $service in $hub_services {
        return true
    }
    let proxy_values = ([$proxy.sender.http $proxy.sender.https $proxy.receiver.http $proxy.receiver.https]
        | where {|value| not ($value | is-empty)}
        | uniq)
    $env_lines | any {|entry|
        let parts = ($entry | split row "=")
        let key = ($parts | first | str upcase)
        let value = ($parts | skip 1 | str join "=")
        ($key in ["HTTP_PROXY" "HTTPS_PROXY"]) and ($value in $proxy_values)
    }
}

# Resolve exactly one running container using compose labels, never fixed IPs.
def inspect-service [stack_id: string, service: string] {
    let result = (try {
        ^docker ps -q --filter $"label=com.docker.compose.project=($stack_id)" --filter $"label=com.docker.compose.service=($service)" | complete
    } catch { {exit_code: 1, stdout: ""} })
    if $result.exit_code != 0 {
        print $"WARNING: cannot resolve MITM endpoint for ($service)"
        return null
    }
    let ids = ($result.stdout | lines | where {|line| not ($line | str trim | is-empty)})
    if ($ids | length) != 1 {
        print $"WARNING: expected one MITM endpoint container for ($service)"
        return null
    }
    let inspected = (try { ^docker inspect ($ids | first) | complete } catch { {exit_code: 1, stdout: ""} })
    if $inspected.exit_code != 0 {
        print $"WARNING: cannot inspect MITM endpoint for ($service)"
        return null
    }
    try { $inspected.stdout | from json | first } catch { null }
}

# No ambiguous service, IP or hostname ownership is written.
export def validate-role-endpoints [roles: record] {
    let endpoints = ($roles | items {|role, value|
        $value.endpoints | each {|endpoint| $endpoint | insert role $role}
    } | flatten)
    for key in ["service" "ipv4"] {
        let values = ($endpoints | get $key)
        if ($values | length) != ($values | uniq | length) {
            error make {msg: $"duplicate MITM endpoint ($key)"}
        }
    }
    let hosts = ($endpoints | each {|endpoint| $endpoint.hosts} | flatten)
    if ($hosts | length) != ($hosts | uniq | length) {
        error make {msg: "duplicate MITM endpoint host"}
    }
}

export def write-mitm-peers [
    artifacts_base: string,
    stack_id: string,
    cell: record,
] {
    let root = (get-ocmts-root)
    let topology = (load-flow-topology $root)
    let sender_platform = ($cell.sender_platform? | default "")
    let receiver_platform = ($cell.receiver_platform? | default "")
    let hub_services = (sender-hub-cookbook-service-names $root $sender_platform ($cell.flow_id? | default "") $topology)
    let proxy = (read-stack-env-proxy ($artifacts_base | path join "compose/inputs/stack.env"))
    let sender_services = (
        ["sender"]
        | append (cookbook-service-names $root $sender_platform "sender")
        | append $hub_services
        | uniq
    )
    let receiver_services = (
        ["receiver"]
        | append (cookbook-service-names $root $receiver_platform "receiver")
        | uniq
    )
    mut roles = {}
    for party in [
        {role: "sender", services: $sender_services}
        {role: "receiver", services: $receiver_services}
        {role: "mitm", services: ["mitm"]}
    ] {
        let endpoints = ($party.services | each {|service|
            let inspected = (inspect-service $stack_id $service)
            if $inspected == null { return null }
            let env_lines = ($inspected.Config.Env? | default [])
            if not (endpoint-is-participant $service $hub_services $env_lines $proxy) { return null }
            endpoint-from-inspect $stack_id $service $inspected
        } | where {|endpoint| $endpoint != null})
        $roles = ($roles | insert $party.role {endpoints: $endpoints})
    }
    validate-role-endpoints $roles
    let peers = {schema_version: 2, roles: $roles, proxy: $proxy}
    let peers_dir = ($artifacts_base | path join "mitm")
    mkdir $peers_dir
    let peers_path = ($peers_dir | path join "peers.json")
    (($peers | to json --indent 2) + "\n") | save --force $peers_path
    print $"MITM peers written: ($peers_path)"
}
