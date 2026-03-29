# Resolve container IPs from Docker labels and write mitm/peers.json.

# Resolve IPv4 for a compose service by querying Docker with label filters.
# Returns empty string when the container or network cannot be found.
def resolve-service-ip [stack_id: string, service: string] {
    let ps_args = [
        "-q"
        "--filter" $"label=com.docker.compose.project=($stack_id)"
        "--filter" $"label=com.docker.compose.service=($service)"
    ]
    let ps = (try {
        ^docker ps ...$ps_args | complete
    } catch {
        {exit_code: 1, stdout: "", stderr: ""}
    })
    if $ps.exit_code != 0 { return "" }
    let container_id = ($ps.stdout | str trim)
    if ($container_id | is-empty) {
        print $"WARNING: no container found for project=($stack_id) service=($service)"
        return ""
    }
    let insp = (try {
        ^docker inspect $container_id | complete
    } catch {
        {exit_code: 1, stdout: "", stderr: ""}
    })
    if $insp.exit_code != 0 {
        print $"WARNING: docker inspect failed for service ($service): ($insp.stderr | str trim)"
        return ""
    }
    try {
        let data = ($insp.stdout | from json)
        let networks = (($data | first).NetworkSettings.Networks)
        let net = (try { $networks | get $stack_id } catch { null })
        if $net == null {
            print $"WARNING: network ($stack_id) not found in inspect for service ($service)"
            return ""
        }
        $net.IPAddress? | default ""
    } catch {|e|
        print $"WARNING: inspect parse failed for service ($service): ($e.msg)"
        ""
    }
}

# Write $artifacts_base/mitm/peers.json with schema_version=1 and role entries.
# Uses Docker label filters (com.docker.compose.project/service) to find
# sender, receiver, and mitm containers by stack_id. Warns and writes partial
# data when an IP cannot be resolved.
export def write-mitm-peers [
    artifacts_base: string,
    stack_id: string,
    cell: record,
] {
    let peers_dir = ($artifacts_base | path join "mitm")
    if not ($peers_dir | path exists) {
        try { mkdir $peers_dir } catch {|e|
            print $"WARNING: could not create mitm dir: ($e.msg)"
        }
    }

    let sender_ip = (resolve-service-ip $stack_id "sender")
    let receiver_ip = (resolve-service-ip $stack_id "receiver")
    let mitm_ip = (resolve-service-ip $stack_id "mitm")

    let sp = ($cell.sender_platform? | default "")
    let rp = ($cell.receiver_platform? | default "")

    let peers = {
        schema_version: 1,
        roles: {
            sender: {
                ipv4: $sender_ip,
                hosts: [$"($sp)1.docker" $"($sp).docker"],
            },
            receiver: {
                ipv4: $receiver_ip,
                hosts: [$"($rp)2.docker"],
            },
            mitm: {
                ipv4: $mitm_ip,
                hosts: ["mitm"],
            },
        },
    }

    let peers_path = ($artifacts_base | path join "mitm" "peers.json")
    (($peers | to json --indent 2) + "\n") | save --force $peers_path
    print $"MITM peers written: ($peers_path)"
}
