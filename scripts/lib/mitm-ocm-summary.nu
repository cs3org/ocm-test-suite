# OCM-aware MITM flow summary writer.
# Reads traffic.jsonl and config/mitm/ocm-extract.nuon, writes under mitm/reports/:
#   02-01-ocm-endpoints.md     (markdown table of endpoint matches)
#   02-02-ocm-endpoints.json   (structured endpoint summary)
#   03-01-ocm-details.md       (per-flow markdown with full captured content)
#   03-02-ocm-details.json     (detail records; optional signature/body objects)
#   03-03-ocm-details.tsv      (detail columns TSV; fully-empty cols removed)
# Loads mitm/peers.json when present to resolve role names.
# Identity backfill from meta/cell.json and meta/run.json when flow fields empty.

use ./domain/core/ocmts-root.nu [get-ocmts-root]
use ./mitm-report-utils.nu [
    participants-from-roles role-primary-host md-participants-preface mk-md-row
    infer-from-role infer-to-role load-meta-identity compute-id-hoist
]

# Match URL+method against the endpoint list from config; returns endpoint id or "".
def match-endpoint-id [url: string, method: string, endpoints: list] {
    let m = ($endpoints | where {|ep|
        ($ep.method == $method) and ($url | str contains $ep.path_prefix)
    })
    if ($m | is-empty) { "" } else { ($m | first).id }
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

# Render a body preview as a Markdown fenced code block.
# Shows pretty JSON when parseable; falls back to raw text; "(no body)" if empty.
def render-body-md [body_str: string, body: any] {
    if ($body_str | str trim | is-empty) { return "(no body)" }
    if $body != null {
        let json_str = (try { $body | to json --indent 2 } catch { $body_str })
        return (["```json" $json_str "```"] | str join "\n")
    }
    ["```" $body_str "```"] | str join "\n"
}

# Build a body-meta record from a request or response sub-record.
# Prefers the body object field when present; otherwise constructs a
# record from top-level content fields (content_encoding, content_length_*,
# content_preview_bytes, content_preview_truncated). Returns null when
# neither form has any data.
def build-body-meta [r: record] {
    let body_obj = ($r.body? | default null)
    if $body_obj != null { return $body_obj }
    mut m = {}
    if ($r.content_encoding? != null) {
        $m = ($m | insert encoding $r.content_encoding)
    }
    if ($r.content_length_decoded? != null) {
        $m = ($m | insert length_decoded $r.content_length_decoded)
    }
    if ($r.content_length_raw? != null) {
        $m = ($m | insert length_raw $r.content_length_raw)
    }
    if ($r.content_preview_bytes? != null) {
        $m = ($m | insert preview_bytes $r.content_preview_bytes)
    }
    if ($r.content_preview_truncated? != null) {
        $m = ($m | insert preview_truncated $r.content_preview_truncated)
    }
    if ($m | columns | is-empty) { null } else { $m }
}

# Build one 03-02 JSON detail record from a processed flow row.
# Core keys always present; from_host/to_host when non-empty; signature/digest/
# discovery/shares/notifications objects included only when non-empty.
def build-det-json-row [r: record] {
    mut rec = {
        captured_at:  $r.captured_at,
        flow_id:      $r.flow_id,
        cell_id:      $r.cell_id,
        run_id:       $r.run_id,
        from_role:    $r.from_role,
        to_role:      $r.to_role,
        endpoint_id:  $r.endpoint_id,
        method:       $r.method,
        status_code:  $r.status_code,
        url:          $r.url,
    }
    if not ($r.from_host | is-empty) {
        $rec = ($rec | insert from_host $r.from_host)
    }
    if not ($r.to_host | is-empty) {
        $rec = ($rec | insert to_host $r.to_host)
    }
    if not ($r.sig_raw | is-empty) {
        $rec = ($rec | insert signature {
            raw:       $r.sig_raw,
            key_id:    $r.sig_key_id,
            algorithm: $r.sig_algorithm,
        })
    }
    if not ($r.digest | is-empty) {
        $rec = ($rec | insert digest $r.digest)
    }
    if $r.endpoint_id == "discovery" {
        if $r.resp_body != null {
            $rec = ($rec | insert discovery {response: $r.resp_body})
        }
    }
    if $r.endpoint_id == "shares" {
        mut shares = {}
        if $r.req_body != null  { $shares = ($shares | insert request  $r.req_body) }
        if $r.resp_body != null { $shares = ($shares | insert response $r.resp_body) }
        if not ($shares | columns | is-empty) {
            $rec = ($rec | insert shares $shares)
        }
    }
    if $r.endpoint_id == "notifications" {
        mut notifs = {}
        if $r.req_body != null  { $notifs = ($notifs | insert request  $r.req_body) }
        if $r.resp_body != null { $notifs = ($notifs | insert response $r.resp_body) }
        if not ($notifs | columns | is-empty) {
            $rec = ($rec | insert notifications $notifs)
        }
    }
    # WebDAV: include request/response body objects with preview text and raw
    # body metadata. XML/text bodies are kept as strings (no JSON parse required).
    if $r.endpoint_id == "webdav" {
        mut wdav = {}
        let req_has_preview = not ($r.req_body_str | str trim | is-empty)
        let req_has_meta    = ($r.req_body_meta != null)
        if ($req_has_preview or $req_has_meta) {
            mut req_bobj = {}
            if $req_has_preview { $req_bobj = ($req_bobj | insert preview $r.req_body_str) }
            if $req_has_meta    { $req_bobj = ($req_bobj | insert meta    $r.req_body_meta) }
            $wdav = ($wdav | insert request {body: $req_bobj})
        }
        let resp_has_preview = not ($r.resp_body_str | str trim | is-empty)
        let resp_has_meta    = ($r.resp_body_meta != null)
        if ($resp_has_preview or $resp_has_meta) {
            mut resp_bobj = {}
            if $resp_has_preview { $resp_bobj = ($resp_bobj | insert preview $r.resp_body_str) }
            if $resp_has_meta    { $resp_bobj = ($resp_bobj | insert meta    $r.resp_body_meta) }
            $wdav = ($wdav | insert response {body: $resp_bobj})
        }
        if not ($wdav | columns | is-empty) {
            $rec = ($rec | insert webdav $wdav)
        }
    }
    $rec
}

# Write OCM-aware summary and details files from mitm/flows/traffic.jsonl.
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

    let participants = (participants-from-roles $roles)
    let preface = (md-participants-preface $participants)

    let raw = (try { open --raw $flows_path } catch {|e|
        print $"WARNING: could not read traffic.jsonl for OCM summary: ($e.msg)"
        return
    })
    let lines = ($raw | lines | where {|l| not ($l | str trim | is-empty)})
    if ($lines | is-empty) {
        print "WARNING: traffic.jsonl is empty; skipping OCM MITM summaries"
        return
    }

    let meta_id = (load-meta-identity $artifacts_base)

    let endpoints = ($cfg.endpoints? | default [])
    let shares_cfg = ($cfg.shares? | default {})
    let shares_req_fields  = ($shares_cfg.request_fields? | default [])
    let shares_resp_fields = ($shares_cfg.response_fields? | default [])
    let headers_cfg = ($cfg.headers? | default {})
    let req_header_names   = ($headers_cfg.request? | default [])
    let resp_header_names  = ($headers_cfg.response? | default [])
    let discovery_cfg = ($cfg.discovery? | default {})
    let discovery_resp_fields = ($discovery_cfg.response_fields? | default [])

    # First pass: extract WebDAV path prefixes advertised in discovery responses.
    # OCM discovery payloads carry resourceTypes[].protocols.webdav path strings.
    # Using these makes WebDAV classification independent of static Nextcloud paths.
    # Derived entries take precedence over static fallbacks in the match pass.
    let disc_eps          = ($endpoints | where {|ep| $ep.id == "discovery"})
    let static_webdav_eps = ($endpoints | where {|ep| $ep.id == "webdav"})
    let non_webdav_eps    = ($endpoints | where {|ep| $ep.id != "webdav"})
    let discovered_webdav_paths = if not ($disc_eps | is-empty) {
        $lines | each {|line|
            try {
                let f    = ($line | from json)
                let req  = ($f.request? | default {})
                let resp = ($f.response? | default {})
                let url    = ($req.url? | default "")
                let method = ($req.method? | default "")
                let is_disc = ($disc_eps | any {|ep|
                    ($ep.method == $method) and ($url | str contains $ep.path_prefix)
                })
                if not $is_disc { null } else {
                    let rb_str = ($resp.body?.preview? | default ($resp.content_preview? | default ""))
                    let rb     = (try { $rb_str | from json } catch { null })
                    if $rb == null { null } else {
                        let rtypes = ($rb.resourceTypes? | default [])
                        let paths = ($rtypes | each {|rt|
                            $rt.protocols?.webdav? | default null
                        } | where {|v| $v != null}
                          | where {|v| not ($v | str trim | is-empty)})
                        if ($paths | is-empty) { null } else { $paths }
                    }
                }
            } catch { null }
        } | where {|v| $v != null}
        | flatten
        | uniq
    } else { [] }

    # Build combined endpoint match list for the main pass:
    #   non-webdav config entries (discovery, shares, notifications, ...)
    #   + discovery-derived webdav entries (all common WebDAV methods)
    #   + static webdav entries from config (fallback for unknown servers)
    let webdav_methods = ["GET" "HEAD" "PUT" "DELETE" "PROPFIND" "MKCOL" "COPY" "MOVE" "OPTIONS"]
    let derived_webdav_eps = ($discovered_webdav_paths | each {|prefix|
        $webdav_methods | each {|m|
            {id: "webdav", method: $m, path_prefix: $prefix, source: "discovery-derived"}
        }
    } | flatten)
    let endpoints_for_match = (
        $non_webdav_eps | append $derived_webdav_eps | append $static_webdav_eps
    )

    let rows = ($lines | each {|line|
        try {
            let f = ($line | from json)
            let req = ($f.request? | default {})
            let resp = ($f.response? | default {})
            let client = ($f.client? | default [])
            let server = ($f.server? | default [])
            let client_ip = (try { $client | get 0 | into string } catch { "" })
            let server_ip = (try { $server | get 0 | into string } catch { "" })
            let req_host    = ($req.host? | default "")
            let method      = ($req.method? | default "")
            let url         = ($req.url? | default "")
            let status_code = ($resp.status_code? | default 0)
            # captured_at takes precedence; ts is the fallback field.
            let captured_at = ($f.captured_at? | default ($f.ts? | default ""))

            let from_role   = (infer-from-role $client_ip $roles)
            let to_role     = (infer-to-role $req_host $server_ip $roles)
            let endpoint_id = (match-endpoint-id $url $method $endpoints_for_match)

            let flow_id_raw = ($f.flow_id? | default "")
            let cell_id_raw = ($f.cell_id? | default "")
            let run_id_raw  = ($f.run_id? | default "")
            let flow_id = if ($flow_id_raw | str trim | is-empty) { $meta_id.flow_id } else { $flow_id_raw }
            let cell_id = if ($cell_id_raw | str trim | is-empty) { $meta_id.cell_id } else { $cell_id_raw }
            let run_id  = if ($run_id_raw  | str trim | is-empty) { $meta_id.run_id  } else { $run_id_raw }

            let req_headers  = ($req.headers? | default {})
            let resp_headers = ($resp.headers? | default {})
            # Build lowercase-key maps so lookups are case-insensitive.
            let req_headers_lc = (
                $req_headers | transpose key val
                | each {|r| {($r.key | str downcase): $r.val}}
                | into record
            )
            let resp_headers_lc = (
                $resp_headers | transpose key val
                | each {|r| {($r.key | str downcase): $r.val}}
                | into record
            )
            let sig_raw = ($req_headers_lc | get --optional "signature" | default "")
            let sig     = (parse-sig-header $sig_raw)
            let digest  = ($req_headers_lc | get --optional "digest" | default "")

            # body.preview takes precedence; content_preview is the fallback field.
            let req_body_str  = ($req.body?.preview?  | default ($req.content_preview?  | default ""))
            let req_body      = (try { $req_body_str  | from json } catch { null })
            let resp_body_str = ($resp.body?.preview? | default ($resp.content_preview? | default ""))
            let resp_body     = (try { $resp_body_str | from json } catch { null })
            # Body meta carries encoding and size alongside the preview string;
            # body object field takes precedence over top-level content fields.
            let req_body_meta  = (build-body-meta $req)
            let resp_body_meta = (build-body-meta $resp)

            let req_header_vals = ($req_header_names | each {|n|
                $req_headers_lc | get --optional ($n | str downcase) | default ""
            })
            let resp_header_vals = ($resp_header_names | each {|n|
                $resp_headers_lc | get --optional ($n | str downcase) | default ""
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

            {
                captured_at:          $captured_at,
                flow_id:              $flow_id,
                cell_id:              $cell_id,
                run_id:               $run_id,
                from_role:            $from_role,
                to_role:              $to_role,
                from_host:            (role-primary-host $from_role $participants),
                to_host:              (role-primary-host $to_role $participants),
                endpoint_id:          $endpoint_id,
                method:               $method,
                status_code:          $status_code,
                url:                  $url,
                sig_raw:              $sig_raw,
                sig_key_id:           $sig.key_id,
                sig_algorithm:        $sig.algorithm,
                digest:               $digest,
                req_body_str:         $req_body_str,
                req_body:             $req_body,
                req_body_meta:        $req_body_meta,
                resp_body_str:        $resp_body_str,
                resp_body:            $resp_body,
                resp_body_meta:       $resp_body_meta,
                req_header_vals:      $req_header_vals,
                resp_header_vals:     $resp_header_vals,
                discovery_resp_vals:  $discovery_resp_vals,
                share_req_vals:       $share_req_vals,
                share_resp_vals:      $share_resp_vals,
            }
        } catch {
            null
        }
    } | where {|r| $r != null})

    let n = ($rows | length)
    let reports_dir = ($artifacts_base | path join "mitm" "reports")
    mkdir $reports_dir

    let has_from_host = ($rows | any {|r| not ($r.from_host | is-empty)})
    let has_to_host   = ($rows | any {|r| not ($r.to_host | is-empty)})

    # For the MD table: suppress host cols when participants preface is present,
    # and hoist invariant identity cols into a short inline preface above the table.
    let suppress_host_cols = not ($preface | is-empty)
    let md_has_from_host = (if $suppress_host_cols { false } else { $has_from_host })
    let md_has_to_host   = (if $suppress_host_cols { false } else { $has_to_host })
    let has_flow_id_ep = ($rows | any {|r| not ($r.flow_id | str trim | is-empty)})
    let has_cell_id_ep = ($rows | any {|r| not ($r.cell_id | str trim | is-empty)})
    let has_run_id_ep  = ($rows | any {|r| not ($r.run_id | str trim | is-empty)})
    let id_hoist = (compute-id-hoist $rows ["flow_id" "cell_id" "run_id"])

    # 02-01-ocm-endpoints.md: markdown table; optional from_host/to_host columns.
    let ep_md_path = ($reports_dir | path join "02-01-ocm-endpoints.md")
    mut ep_col_names = ["captured_at"]
    if ($has_flow_id_ep and not ("flow_id" in $id_hoist.skip_cols)) {
        $ep_col_names = ($ep_col_names | append ["flow_id"])
    }
    if ($has_cell_id_ep and not ("cell_id" in $id_hoist.skip_cols)) {
        $ep_col_names = ($ep_col_names | append ["cell_id"])
    }
    if ($has_run_id_ep and not ("run_id" in $id_hoist.skip_cols)) {
        $ep_col_names = ($ep_col_names | append ["run_id"])
    }
    $ep_col_names = ($ep_col_names | append ["from_role"])
    if $md_has_from_host { $ep_col_names = ($ep_col_names | append ["from_host"]) }
    $ep_col_names = ($ep_col_names | append ["to_role"])
    if $md_has_to_host   { $ep_col_names = ($ep_col_names | append ["to_host"]) }
    $ep_col_names = ($ep_col_names | append ["endpoint_id" "method" "status" "url"])
    let ep_col_names = $ep_col_names
    let ep_md_header = (mk-md-row $ep_col_names)
    let ep_md_sep    = (mk-md-row ($ep_col_names | each {|_| "---"}))
    let ep_md_rows = ($rows | each {|r|
        mut vals = [$r.captured_at]
        if ($has_flow_id_ep and not ("flow_id" in $id_hoist.skip_cols)) {
            $vals = ($vals | append [$r.flow_id])
        }
        if ($has_cell_id_ep and not ("cell_id" in $id_hoist.skip_cols)) {
            $vals = ($vals | append [$r.cell_id])
        }
        if ($has_run_id_ep and not ("run_id" in $id_hoist.skip_cols)) {
            $vals = ($vals | append [$r.run_id])
        }
        $vals = ($vals | append [$r.from_role])
        if $md_has_from_host { $vals = ($vals | append [$r.from_host]) }
        $vals = ($vals | append [$r.to_role])
        if $md_has_to_host   { $vals = ($vals | append [$r.to_host]) }
        $vals = ($vals | append [$r.endpoint_id $r.method ($r.status_code | into string) $r.url])
        mk-md-row $vals
    })
    let ep_table_str = (([$ep_md_header $ep_md_sep] | append $ep_md_rows | str join "\n") + "\n")
    let ep_header_preface = if ($preface | is-empty) { "" } else { $preface + "\n" }
    let ep_md_content = $ep_header_preface + $id_hoist.preface + $ep_table_str
    $ep_md_content | save --force $ep_md_path

    # 02-02-ocm-endpoints.json: structured endpoint summary.
    # Optional participants key; from_host/to_host per row when any present.
    let ep_json_path = ($reports_dir | path join "02-02-ocm-endpoints.json")
    let ep_json_rows = ($rows | each {|r|
        mut row = {
            captured_at:  $r.captured_at,
            flow_id:      $r.flow_id,
            cell_id:      $r.cell_id,
            run_id:       $r.run_id,
            from_role:    $r.from_role,
        }
        if $has_from_host { $row = ($row | insert from_host $r.from_host) }
        $row = ($row | insert to_role $r.to_role)
        if $has_to_host   { $row = ($row | insert to_host $r.to_host) }
        $row = ($row
            | insert endpoint_id  $r.endpoint_id
            | insert method       $r.method
            | insert status_code  $r.status_code
            | insert url          $r.url)
        $row
    })
    mut ep_json_summary = {total_flows: $n, flows: $ep_json_rows}
    if not ($preface | is-empty) {
        $ep_json_summary = ($ep_json_summary | insert participants $participants)
    }
    (($ep_json_summary | to json --indent 2) + "\n") | save --force $ep_json_path

    # 03-01-ocm-details.md: participants preface once at top; per-flow sections
    # use from_role -> to_role heading only (no per-flow sender/receiver lines).
    let det_md_path = ($reports_dir | path join "03-01-ocm-details.md")
    let det_md_sections = ($rows | enumerate | each {|e|
        let r = $e.item
        let idx = ($e.index + 1)
        let ep = if ($r.endpoint_id | is-empty) { "unknown" } else { $r.endpoint_id }
        mut lines = [$"## Flow ($idx): ($ep) ($r.method) ($r.status_code) - ($r.from_role) -> ($r.to_role)"]
        $lines = ($lines | append ["" $"- **captured_at**: ($r.captured_at)"])
        mut id_parts = []
        if not ($r.flow_id | str trim | is-empty) {
            $id_parts = ($id_parts | append $"flow_id=($r.flow_id)")
        }
        if not ($r.cell_id | str trim | is-empty) {
            $id_parts = ($id_parts | append $"cell_id=($r.cell_id)")
        }
        if not ($r.run_id | str trim | is-empty) {
            $id_parts = ($id_parts | append $"run_id=($r.run_id)")
        }
        if not ($id_parts | is-empty) {
            let id_str = ($id_parts | str join " | ")
            $lines = ($lines | append $"- **identity**: ($id_str)")
        }
        $lines = ($lines | append [
            $"- **endpoint_id**: ($ep)"
            $"- **status_code**: ($r.status_code)"
            $"- **url**: <($r.url)>"
            ""
        ])
        if not ($r.sig_raw | is-empty) {
            $lines = ($lines | append ["**Signature**:" "" "```" $r.sig_raw "```" ""])
        } else {
            $lines = ($lines | append ["**Signature**: (none)" ""])
        }
        if not ($r.digest | is-empty) {
            $lines = ($lines | append [$"**Digest**: `($r.digest)`" ""])
        } else {
            $lines = ($lines | append ["**Digest**: (none)" ""])
        }
        $lines = ($lines | append ["### Request body" ""])
        $lines = ($lines | append [(render-body-md $r.req_body_str $r.req_body) ""])
        $lines = ($lines | append ["### Response body" ""])
        $lines = ($lines | append [(render-body-md $r.resp_body_str $r.resp_body) ""])
        $lines = ($lines | append ["---" ""])
        $lines | str join "\n"
    })
    let det_md_intro = if ($preface | is-empty) {
        "# OCM Flow Details\n\n---\n\n"
    } else {
        ("# OCM Flow Details\n\n" + $preface + "\n---\n\n")
    }
    let det_md_content = ($det_md_intro + ($det_md_sections | str join "\n"))
    ($det_md_content + "\n") | save --force $det_md_path

    # 03-02-ocm-details.json: list of detail records; from_host/to_host when present.
    let det_json_path = ($reports_dir | path join "03-02-ocm-details.json")
    let det_json_rows = ($rows | each {|r| build-det-json-row $r})
    (($det_json_rows | to json --indent 2) + "\n") | save --force $det_json_path

    # 03-03-ocm-details.tsv: wide TSV; from_host/to_host near from_role/to_role.
    # Fully-empty columns are dropped after building all row values.
    let det_tsv_path = ($reports_dir | path join "03-03-ocm-details.tsv")
    let det_col_names = (
        ["captured_at" "flow_id" "cell_id" "run_id"
         "from_role" "from_host" "to_role" "to_host"
         "endpoint_id" "method" "status_code" "url"
         "sig_key_id" "sig_algorithm" "digest"]
        | append ($req_header_names | each {|n| $"req_h_($n)"})
        | append ($resp_header_names | each {|n| $"resp_h_($n)"})
        | append ($discovery_resp_fields | each {|f|
            let col = ($f | str replace --all "." "_")
            $"disc_($col)"
        })
        | append $shares_req_fields
        | append $shares_resp_fields
    )
    let tsv_raw_rows = ($rows | each {|r|
        [$r.captured_at $r.flow_id $r.cell_id $r.run_id
         $r.from_role $r.from_host $r.to_role $r.to_host
         $r.endpoint_id $r.method $r.status_code $r.url
         $r.sig_key_id $r.sig_algorithm $r.digest]
        | append $r.req_header_vals
        | append $r.resp_header_vals
        | append $r.discovery_resp_vals
        | append $r.share_req_vals
        | append $r.share_resp_vals
        | each {|v| $v | into string}
    })
    # Find column indices that have at least one non-empty value across all rows.
    let kept_col_pairs = if ($tsv_raw_rows | is-empty) {
        $det_col_names | enumerate | each {|e| {index: $e.index, name: $e.item}}
    } else {
        $det_col_names | enumerate | where {|e|
            let i = $e.index
            not ($tsv_raw_rows | all {|row| ($row | get $i | str trim | is-empty)})
        } | each {|e| {index: $e.index, name: $e.item}}
    }
    let final_tsv_header = ($kept_col_pairs | each {|c| $c.name} | str join "\t")
    let final_tsv_rows = ($tsv_raw_rows | each {|row_vals|
        $kept_col_pairs
        | each {|c| sanitize-for-tsv ($row_vals | get $c.index)}
        | str join "\t"
    })
    (([$final_tsv_header] | append $final_tsv_rows | str join "\n") + "\n")
        | save --force $det_tsv_path

    print $"OCM MITM summaries: ($n) flows ->"
    print $"  ($ep_md_path)"
    print $"  ($ep_json_path)"
    print $"  ($det_md_path)"
    print $"  ($det_json_path)"
    print $"  ($det_tsv_path)"
}
