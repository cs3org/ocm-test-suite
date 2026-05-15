# MITM traffic flow summarizer.
# Reads mitm/flows/traffic.jsonl and writes reports under mitm/reports/:
#   01-01-traffic-overview.md   (markdown table)
#   01-02-traffic-overview.json (structured summary)
#   99-traffic-pretty.json      (full flows pretty-printed)
# Loads mitm/peers.json when present to resolve from_role and to_role.
# Identity backfill from meta/cell.json and meta/run.json when flow fields empty.
# Safe when the jsonl file is missing or empty.

use ./report-utils.nu [
    participants-from-roles role-primary-host md-participants-preface mk-md-row
    infer-from-role infer-to-role load-meta-identity compute-id-hoist
]

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

    let peers_path = ($artifacts_base | path join "mitm" "peers.json")
    let roles = if ($peers_path | path exists) {
        try { (open $peers_path).roles? | default {} } catch { {} }
    } else { {} }

    let participants = (participants-from-roles $roles)
    let preface = (md-participants-preface $participants)

    let meta_id = (load-meta-identity $artifacts_base)

    let flows = ($lines | each {|line|
        try { $line | from json } catch { null }
    } | where {|o| $o != null})

    let n = ($flows | length)
    if $n == 0 {
        print "WARNING: no valid flows parsed in traffic.jsonl; skipping MITM summary"
        return
    }

    let reports_dir = ($artifacts_base | path join "mitm" "reports")
    mkdir $reports_dir

    let rows = ($flows | each {|f|
        try {
            let req = ($f.request? | default {})
            let resp = ($f.response? | default {})
            let client = ($f.client? | default [])
            let server = ($f.server? | default [])
            let client_ip = (try { $client | get 0 | into string } catch { "" })
            let server_ip = (try { $server | get 0 | into string } catch { "" })
            # captured_at takes precedence; ts is the fallback field.
            let captured_at = ($f.captured_at? | default ($f.ts? | default ""))
            let flow_id_raw = ($f.flow_id? | default "")
            let cell_id_raw = ($f.cell_id? | default "")
            let run_id_raw = ($f.run_id? | default "")
            let flow_id = if ($flow_id_raw | str trim | is-empty) { $meta_id.flow_id } else { $flow_id_raw }
            let cell_id = if ($cell_id_raw | str trim | is-empty) { $meta_id.cell_id } else { $cell_id_raw }
            let run_id = if ($run_id_raw | str trim | is-empty) { $meta_id.run_id } else { $run_id_raw }
            let from_role = (infer-from-role $client_ip $roles)
            let to_role = (infer-to-role ($req.host? | default "") $server_ip $roles)
            {
                captured_at: $captured_at,
                event_id:    ($f.event_id? | default ""),
                exchange_id: ($f.exchange_id? | default ""),
                flow_id:     $flow_id,
                cell_id:     $cell_id,
                run_id:      $run_id,
                from_role:   $from_role,
                to_role:     $to_role,
                from_host:   (role-primary-host $from_role $participants),
                to_host:     (role-primary-host $to_role $participants),
                method:      ($req.method? | default ""),
                status_code: ($resp.status_code? | default 0),
                url:         ($req.url? | default ""),
            }
        } catch {
            null
        }
    } | where {|r| $r != null})

    # Check which identity and host columns have any non-empty value.
    # Omit columns that remain entirely empty from MD and JSON outputs.
    let has_flow_id   = ($rows | any {|r| not ($r.flow_id | str trim | is-empty)})
    let has_cell_id   = ($rows | any {|r| not ($r.cell_id | str trim | is-empty)})
    let has_run_id    = ($rows | any {|r| not ($r.run_id | str trim | is-empty)})
    let has_from_host = ($rows | any {|r| not ($r.from_host | is-empty)})
    let has_to_host   = ($rows | any {|r| not ($r.to_host | is-empty)})

    # For the MD table: suppress host cols when participants preface is present,
    # and hoist invariant identity cols into a short inline preface above the table.
    let suppress_host_cols = not ($preface | is-empty)
    let md_has_from_host = (if $suppress_host_cols { false } else { $has_from_host })
    let md_has_to_host   = (if $suppress_host_cols { false } else { $has_to_host })
    let id_hoist = (compute-id-hoist $rows ["flow_id" "cell_id" "run_id"])

    # 01-01-traffic-overview.md
    let md_path = ($reports_dir | path join "01-01-traffic-overview.md")
    mut md_col_names = ["captured_at"]
    if ($has_flow_id and not ("flow_id" in $id_hoist.skip_cols)) {
        $md_col_names = ($md_col_names | append ["flow_id"])
    }
    if ($has_cell_id and not ("cell_id" in $id_hoist.skip_cols)) {
        $md_col_names = ($md_col_names | append ["cell_id"])
    }
    if ($has_run_id and not ("run_id" in $id_hoist.skip_cols)) {
        $md_col_names = ($md_col_names | append ["run_id"])
    }
    $md_col_names = ($md_col_names | append ["from_role"])
    if $md_has_from_host { $md_col_names = ($md_col_names | append ["from_host"]) }
    $md_col_names = ($md_col_names | append ["to_role"])
    if $md_has_to_host   { $md_col_names = ($md_col_names | append ["to_host"]) }
    $md_col_names = ($md_col_names | append ["method" "status" "url"])
    let md_col_names = $md_col_names
    let md_header = (mk-md-row $md_col_names)
    let md_sep    = (mk-md-row ($md_col_names | each {|_| "---"}))
    let md_rows = ($rows | each {|r|
        let status = ($r.status_code | into string)
        mut vals = [$r.captured_at]
        if ($has_flow_id and not ("flow_id" in $id_hoist.skip_cols)) {
            $vals = ($vals | append [$r.flow_id])
        }
        if ($has_cell_id and not ("cell_id" in $id_hoist.skip_cols)) {
            $vals = ($vals | append [$r.cell_id])
        }
        if ($has_run_id and not ("run_id" in $id_hoist.skip_cols)) {
            $vals = ($vals | append [$r.run_id])
        }
        $vals = ($vals | append [$r.from_role])
        if $md_has_from_host { $vals = ($vals | append [$r.from_host]) }
        $vals = ($vals | append [$r.to_role])
        if $md_has_to_host   { $vals = ($vals | append [$r.to_host]) }
        $vals = ($vals | append [$r.method $status $r.url])
        mk-md-row $vals
    })
    let table_str = (([$md_header $md_sep] | append $md_rows | str join "\n") + "\n")
    let header_preface = if ($preface | is-empty) { "" } else { $preface + "\n" }
    let md_content = $header_preface + $id_hoist.preface + $table_str
    $md_content | save --force $md_path

    # 01-02-traffic-overview.json
    # Optional participants key added when host mapping is non-empty.
    # from_host/to_host added per row only when any row has a non-empty value.
    let json_summary_path = ($reports_dir | path join "01-02-traffic-overview.json")
    let json_rows = ($rows | each {|r|
        mut row = {captured_at: $r.captured_at}
        if $has_flow_id { $row = ($row | insert flow_id $r.flow_id) }
        if $has_cell_id { $row = ($row | insert cell_id $r.cell_id) }
        if $has_run_id  { $row = ($row | insert run_id $r.run_id) }
        $row = ($row | insert from_role $r.from_role)
        if $has_from_host { $row = ($row | insert from_host $r.from_host) }
        $row = ($row | insert to_role $r.to_role)
        if $has_to_host   { $row = ($row | insert to_host $r.to_host) }
        $row = ($row
            | insert method      $r.method
            | insert status_code $r.status_code
            | insert url         $r.url)
        $row
    })
    mut json_summary = {total_flows: $n, flows: $json_rows}
    if not ($preface | is-empty) {
        $json_summary = ($json_summary | insert participants $participants)
    }
    (($json_summary | to json --indent 2) + "\n") | save --force $json_summary_path

    # 99-traffic-pretty.json: full raw flows pretty-printed (no identity backfill).
    let pretty_path = ($reports_dir | path join "99-traffic-pretty.json")
    (($flows | to json --indent 2) + "\n") | save --force $pretty_path

    print $"MITM summary: ($n) flows ->"
    print $"  ($md_path)"
    print $"  ($json_summary_path)"
    print $"  ($pretty_path)"
}
