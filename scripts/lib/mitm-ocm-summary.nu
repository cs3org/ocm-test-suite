# OCM-aware MITM flow summary writer.
# Reads traffic.jsonl and config/mitm/ocm-extract.nuon, writes:
#   mitm/flows/traffic.ocm.summary.tsv  (ts, from_role, to_role, endpoint_id, method, status_code, url)
#   mitm/flows/traffic.ocm.details.tsv  (above + sig fields, digest, headers, discovery/shares body fields)
# Loads mitm/peers.json when present to resolve role names.

use ./domain/core/ocmts-root.nu [get-ocmts-root]

# Match URL+method against the endpoint list from config; returns endpoint id or "".
def match-endpoint-id [url: string, method: string, endpoints: list] {
    let m = ($endpoints | where {|ep|
        ($ep.method == $method) and ($url | str contains $ep.path_prefix)
    })
    if ($m | is-empty) { "" } else { ($m | first).id }
}

# Infer source role from a client IP against the peers role map.
def infer-from-role-ocm [client_ip: string, roles: record] {
    if ($client_ip | is-empty) { return "unknown" }
    let m = ($roles | items {|name, r|
        if ($r.ipv4? | default "") == $client_ip { $name } else { null }
    } | where {|v| $v != null})
    if ($m | is-empty) { "unknown" } else { $m | first }
}

# Infer destination role from request host and server IP.
# Host match against role.hosts takes priority over server IP match.
def infer-to-role-ocm [req_host: string, server_ip: string, roles: record] {
    let hm = ($roles | items {|name, r|
        if $req_host in ($r.hosts? | default []) { $name } else { null }
    } | where {|v| $v != null})
    if not ($hm | is-empty) { return ($hm | first) }
    if ($server_ip | is-empty) { return "unknown" }
    let im = ($roles | items {|name, r|
        if ($r.ipv4? | default "") == $server_ip { $name } else { null }
    } | where {|v| $v != null})
    if ($im | is-empty) { "unknown" } else { $im | first }
}

# Parse keyId and algorithm from an HTTP Signature header value.
def parse-sig-header [sig: string] {
    let key_id = (try {
        $sig | parse --regex 'keyId="(?P<v>[^"]*)"' | first | get v
    } catch { "" })
    let alg = (try {
        $sig | parse --regex 'algorithm="(?P<v>[^"]*)"' | first | get v
    } catch { "" })
    {key_id: $key_id, algorithm: $alg}
}

# Extract a named field from a parsed JSON body record.
# Returns empty string when the field is absent, null, or not serializable.
def safe-field [body: any, field: string] {
    let v = (try { $body | get $field } catch { null })
    if $v == null { return "" }
    let t = ($v | describe)
    if $t == "string" { $v } else if ($t in ["int" "float" "bool"]) {
        $v | into string
    } else {
        try { $v | to json --indent 0 } catch { "" }
    }
}

# Resolve a dotted path (e.g. "publicKey.keyId") through nested records.
# Returns empty string when any segment is absent or body is null.
def safe-dotted-field [body: any, path: string] {
    let parts = ($path | split row ".")
    let v = (try {
        $parts | reduce --fold $body {|key, acc|
            if $acc == null { null } else {
                try { $acc | get $key } catch { null }
            }
        }
    } catch { null })
    if $v == null { return "" }
    let t = ($v | describe)
    if $t == "string" { $v } else if ($t in ["int" "float" "bool"]) {
        $v | into string
    } else {
        try { $v | to json --indent 0 } catch { "" }
    }
}

# Sanitize a string for TSV output: replace tabs and newlines with spaces.
def sanitize-for-tsv [s: string] {
    $s
    | str replace --all (char tab) " "
    | str replace --all (char newline) " "
    | str replace --all (char cr) " "
}

# Write OCM-aware summary and details TSV files from mitm/flows/traffic.jsonl.
# Config is read from {repo_root}/config/mitm/ocm-extract.nuon.
# Peers are loaded from mitm/peers.json when present.
export def write-ocm-mitm-summaries [artifacts_base: string] {
    let flows_path = ($artifacts_base | path join "mitm" "flows" "traffic.jsonl")
    if not ($flows_path | path exists) {
        print "WARNING: traffic.jsonl not found; skipping OCM MITM summaries"
        return
    }

    let root = (get-ocmts-root)
    let cfg_path = ($root | path join "config" "mitm" "ocm-extract.nuon")
    if not ($cfg_path | path exists) {
        print $"WARNING: ($cfg_path) not found; skipping OCM MITM summaries"
        return
    }
    let cfg = (try { open $cfg_path } catch {|e|
        print $"WARNING: could not read ocm-extract.nuon: ($e.msg)"
        return
    })

    let peers_path = ($artifacts_base | path join "mitm" "peers.json")
    let roles = if ($peers_path | path exists) {
        try { (open $peers_path).roles? | default {} } catch { {} }
    } else { {} }

    let raw = (try { open --raw $flows_path } catch {|e|
        print $"WARNING: could not read traffic.jsonl for OCM summary: ($e.msg)"
        return
    })
    let lines = ($raw | lines | where {|l| not ($l | str trim | is-empty)})
    if ($lines | is-empty) {
        print "WARNING: traffic.jsonl is empty; skipping OCM MITM summaries"
        return
    }

    let endpoints = ($cfg.endpoints? | default [])
    let shares_cfg = ($cfg.shares? | default {})
    let shares_req_fields = ($shares_cfg.request_fields? | default [])
    let shares_resp_fields = ($shares_cfg.response_fields? | default [])
    let headers_cfg = ($cfg.headers? | default {})
    let req_header_names = ($headers_cfg.request? | default [])
    let resp_header_names = ($headers_cfg.response? | default [])
    let discovery_cfg = ($cfg.discovery? | default {})
    let discovery_resp_fields = ($discovery_cfg.response_fields? | default [])

    let sum_header = "ts\tfrom_role\tto_role\tendpoint_id\tmethod\tstatus_code\turl"
    let det_header = (
        ["ts" "from_role" "to_role" "endpoint_id" "method" "status_code" "url"
         "sig_key_id" "sig_algorithm" "digest"]
        | append ($req_header_names | each {|n| $"req_h_($n)"})
        | append ($resp_header_names | each {|n| $"resp_h_($n)"})
        | append ($discovery_resp_fields | each {|f|
            let col = ($f | str replace --all "." "_")
            $"disc_($col)"
        })
        | append $shares_req_fields
        | append $shares_resp_fields
        | str join "\t"
    )

    let rows_pair = ($lines | each {|line|
        try {
            let f = ($line | from json)
            let req = ($f.request? | default {})
            let resp = ($f.response? | default {})
            let client = ($f.client? | default [])
            let server = ($f.server? | default [])
            let client_ip = (try { $client | get 0 | into string } catch { "" })
            let server_ip = (try { $server | get 0 | into string } catch { "" })
            let req_host = ($req.host? | default "")
            let method = ($req.method? | default "")
            let url = ($req.url? | default "")
            let status_code = ($resp.status_code? | default 0 | into string)
            let ts = ($f.ts? | default "")

            let from_role = (infer-from-role-ocm $client_ip $roles)
            let to_role = (infer-to-role-ocm $req_host $server_ip $roles)
            let endpoint_id = (match-endpoint-id $url $method $endpoints)

            let req_headers = ($req.headers? | default {})
            let resp_headers = ($resp.headers? | default {})
            let sig_raw = (try { $req_headers | get "Signature" } catch { "" })
            let sig = (parse-sig-header $sig_raw)
            let digest = (try { $req_headers | get "Digest" } catch { "" })

            let req_body = (try {
                $req.content_preview? | default "" | from json
            } catch { null })
            let resp_body = (try {
                $resp.content_preview? | default "" | from json
            } catch { null })

            let req_header_vals = ($req_header_names | each {|n|
                try { $req_headers | get $n } catch { "" }
            })
            let resp_header_vals = ($resp_header_names | each {|n|
                try { $resp_headers | get $n } catch { "" }
            })
            let discovery_resp_vals = ($discovery_resp_fields | each {|field|
                if ($endpoint_id == "discovery" and $resp_body != null) {
                    safe-dotted-field $resp_body $field
                } else { "" }
            })
            let share_req_vals = ($shares_req_fields | each {|field|
                if ($endpoint_id == "shares" and $req_body != null) {
                    safe-field $req_body $field
                } else { "" }
            })
            let share_resp_vals = ($shares_resp_fields | each {|field|
                if ($endpoint_id == "shares" and $resp_body != null) {
                    safe-field $resp_body $field
                } else { "" }
            })

            let sum_row = (
                [$ts $from_role $to_role $endpoint_id $method $status_code $url]
                | each {|v| sanitize-for-tsv ($v | into string)}
                | str join "\t"
            )
            let det_row = (
                [$ts $from_role $to_role $endpoint_id $method $status_code $url
                 $sig.key_id $sig.algorithm $digest]
                | append $req_header_vals
                | append $resp_header_vals
                | append $discovery_resp_vals
                | append $share_req_vals
                | append $share_resp_vals
                | each {|v| sanitize-for-tsv ($v | into string)}
                | str join "\t"
            )

            {sum: $sum_row, det: $det_row}
        } catch {
            null
        }
    } | where {|r| $r != null})

    let n = ($rows_pair | length)
    let sum_path = ($artifacts_base | path join "mitm" "flows" "traffic.ocm.summary.tsv")
    let det_path = ($artifacts_base | path join "mitm" "flows" "traffic.ocm.details.tsv")

    ([$sum_header] | append ($rows_pair | each {|r| $r.sum}) | str join "\n")
        | save --force $sum_path
    ([$det_header] | append ($rows_pair | each {|r| $r.det}) | str join "\n")
        | save --force $det_path

    print $"OCM MITM summaries: ($n) flows -> ($sum_path) + ($det_path)"
}
