# MITM traffic flow summarizer.
# Reads mitm/flows/traffic.jsonl from an artifacts dir and writes:
#   mitm/flows/traffic.summary.tsv  (ts, from_role, to_role, method, status_code, url)
#   mitm/flows/traffic.pretty.json
# Loads mitm/peers.json when present to resolve from_role and to_role.
# Safe when the jsonl file is missing or empty.

# Infer source role from a client IP against the peers role map.
def infer-from-role [client_ip: string, roles: record] {
    if ($client_ip | is-empty) { return "unknown" }
    let matches = ($roles | items {|name, r|
        if ($r.ipv4? | default "") == $client_ip { $name } else { null }
    } | where {|v| $v != null})
    if ($matches | is-empty) { "unknown" } else { $matches | first }
}

# Infer destination role from request host and server IP.
# Host match against role.hosts takes priority over server IP match.
def infer-to-role [req_host: string, server_ip: string, roles: record] {
    let host_matches = ($roles | items {|name, r|
        if $req_host in ($r.hosts? | default []) { $name } else { null }
    } | where {|v| $v != null})
    if not ($host_matches | is-empty) { return ($host_matches | first) }
    if ($server_ip | is-empty) { return "unknown" }
    let ip_matches = ($roles | items {|name, r|
        if ($r.ipv4? | default "") == $server_ip { $name } else { null }
    } | where {|v| $v != null})
    if ($ip_matches | is-empty) { "unknown" } else { $ip_matches | first }
}

export def summarize-mitm-flows [artifacts_base: string] {
    let flows_path = ($artifacts_base | path join "mitm" "flows" "traffic.jsonl")
    if not ($flows_path | path exists) {
        print "WARNING: mitm/flows/traffic.jsonl not found; skipping MITM summary"
        return
    }
    let raw = try {
        open --raw $flows_path
    } catch {|e|
        print $"WARNING: could not read traffic.jsonl: ($e.msg)"
        return
    }
    let lines = ($raw | lines | where {|l| not ($l | str trim | is-empty)})
    if ($lines | is-empty) {
        print "WARNING: traffic.jsonl is empty; skipping MITM summary"
        return
    }

    # Load peers for role inference; gracefully absent.
    let peers_path = ($artifacts_base | path join "mitm" "peers.json")
    let roles = if ($peers_path | path exists) {
        try { (open $peers_path).roles? | default {} } catch { {} }
    } else { {} }

    let flows = ($lines | each {|line|
        try { $line | from json } catch { null }
    } | where {|o| $o != null})

    let n = ($flows | length)
    if $n == 0 {
        print "WARNING: no valid flows parsed in traffic.jsonl; skipping MITM summary"
        return
    }

    let rows = ($flows | each {|f|
        try {
            let req = ($f.request? | default {})
            let resp = ($f.response? | default {})
            let client = ($f.client? | default [])
            let server = ($f.server? | default [])
            let client_ip = (try { $client | get 0 | into string } catch { "" })
            let server_ip = (try { $server | get 0 | into string } catch { "" })
            {
                ts: ($f.ts? | default ""),
                from_role: (infer-from-role $client_ip $roles),
                to_role: (infer-to-role ($req.host? | default "") $server_ip $roles),
                method: ($req.method? | default ""),
                status_code: ($resp.status_code? | default 0),
                url: ($req.url? | default ""),
            }
        } catch {
            null
        }
    } | where {|r| $r != null})

    let tsv_path = ($artifacts_base | path join "mitm" "flows" "traffic.summary.tsv")
    let header = "ts\tfrom_role\tto_role\tmethod\tstatus_code\turl"
    let body = ($rows | each {|r|
        [$r.ts $r.from_role $r.to_role $r.method ($r.status_code | into string) $r.url]
        | str join "\t"
    })
    ([$header] | append $body | str join "\n") | save --force $tsv_path

    let json_path = ($artifacts_base | path join "mitm" "flows" "traffic.pretty.json")
    (($flows | to json --indent 2) + "\n") | save --force $json_path
    print $"MITM summary: ($n) flows -> ($tsv_path) + ($json_path)"
}
