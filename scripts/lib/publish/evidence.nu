# Emit the evidence sidecar (meta/evidence.v1.json) for a completed run.
# Enumerates all structured/text artifacts in a cell's artifact directory.

use ../time/utc.nu [utc-now]

def hash-and-size [abs_path: string] {
    let size_bytes = try {
        ls $abs_path | get size | first | into int
    } catch {
        0
    }
    let sha_result = (try {
        ^sha256sum $abs_path | complete
    } catch {
        {exit_code: 127, stdout: "", stderr: ""}
    })
    let sha256 = if (($sha_result.exit_code != 0) or ($sha_result.stdout | is-empty)) {
        print --stderr $"WARNING: sha256sum failed for ($abs_path)"
        ""
    } else {
        $sha_result.stdout | split row " " | first | str downcase | str trim
    }
    {size_bytes: $size_bytes, sha256: $sha256}
}

def count-jsonl-records [abs_path: string] {
    try { open --raw $abs_path | lines | length } catch { 0 }
}

# Returns stub_reason string if the file is a sentinel stub, else null.
def detect-stub [abs_path: string, size_bytes: int] {
    if $size_bytes >= 256 { return null }
    let lines_vec = (try { open --raw $abs_path | lines } catch { [] })
    let first_line = if ($lines_vec | is-empty) { "" } else { $lines_vec | first }
    if ($first_line | str starts-with "SKIPPED:") {
        $first_line | str replace "SKIPPED:" "" | str trim
    } else {
        null
    }
}

def make-item [abs_base: string, rel: string, logical: string, envelope: string, tab: string] {
    let abs_path = ($abs_base | path join $rel)
    let hs = (hash-and-size $abs_path)
    {
        path: $rel,
        logical_name: $logical,
        envelope: $envelope,
        tab: $tab,
        size_bytes: $hs.size_bytes,
        sha256: $hs.sha256,
    }
}

def collect-meta-items [abs_base: string] {
    let map = [
        {rel: "meta/run.json", logical: "run"}
        {rel: "meta/result.v1.json", logical: "result"}
        {rel: "meta/cell.json", logical: "cell"}
        {rel: "meta/images.v1.json", logical: "images"}
    ]
    $map | where {|m| ($abs_base | path join $m.rel) | path exists}
        | each {|m| make-item $abs_base $m.rel $m.logical "jsonl.v1" "meta"}
}

def collect-stack-items [abs_base: string] {
    mut items = []

    if (($abs_base | path join "compose/manifest.v1.json") | path exists) {
        $items = ($items | append (
            make-item $abs_base "compose/manifest.v1.json" "stack" "jsonl.v1" "stack"
        ))
    }

    let yml_abs = (try { glob ($abs_base | path join "compose/inputs/*.yml") } catch { [] })
    for p in $yml_abs {
        let fname = ($p | path basename)
        let stem = ($p | path parse | get stem)
        let rel = $"compose/inputs/($fname)"
        $items = ($items | append (
            (make-item $abs_base $rel $stem "text-log.v1" "stack") | insert language "yaml"
        ))
    }

    if (($abs_base | path join "compose/inputs/stack.env") | path exists) {
        $items = ($items | append (
            (make-item $abs_base "compose/inputs/stack.env" "stack.env" "text-log.v1" "stack")
            | insert language "env"
        ))
    }

    let resolved_abs = (try {
        glob ($abs_base | path join "compose/compose.resolved*.yml")
    } catch { [] })
    for p in $resolved_abs {
        let fname = ($p | path basename)
        let stem = ($p | path parse | get stem)
        let rel = $"compose/($fname)"
        $items = ($items | append (
            (make-item $abs_base $rel $stem "text-log.v1" "stack") | insert language "yaml"
        ))
    }

    $items
}

def collect-logs-items [abs_base: string] {
    mut items = []

    let cypress_run_abs = ($abs_base | path join "docker/logs/cypress-run.log")
    if ($cypress_run_abs | path exists) {
        $items = ($items | append (
            (make-item $abs_base "docker/logs/cypress-run.log" "cypress-run.log" "text-log.v1" "logs")
            | insert ansi true
            | insert truncated false
        ))
    }

    let all_log_abs = (try { glob ($abs_base | path join "docker/logs/*.log") } catch { [] })
    for p in $all_log_abs {
        let fname = ($p | path basename)
        if $fname == "cypress-run.log" { continue }
        let svc = ($p | path parse | get stem)
        let rel = $"docker/logs/($fname)"
        let hs = (hash-and-size $p)
        let stub_reason = (detect-stub $p $hs.size_bytes)
        if $stub_reason != null {
            $items = ($items | append {
                path: $rel,
                logical_name: $fname,
                envelope: "stub.v1",
                tab: "logs",
                size_bytes: $hs.size_bytes,
                sha256: $hs.sha256,
                service: $svc,
                stub_reason: $stub_reason,
            })
        } else {
            $items = ($items | append {
                path: $rel,
                logical_name: $fname,
                envelope: "text-log.v1",
                tab: "logs",
                size_bytes: $hs.size_bytes,
                sha256: $hs.sha256,
                service: $svc,
                truncated: false,
            })
        }
    }

    $items
}

def collect-mitm-items [abs_base: string] {
    mut items = []

    let fixed = [
        {rel: "mitm/flows/traffic.jsonl", logical: "traffic", envelope: "event-stream.v1"}
        {rel: "mitm/flows/session.json", logical: "session", envelope: "jsonl.v1"}
        {rel: "mitm/redaction-report.json", logical: "redaction-report", envelope: "jsonl.v1"}
        {rel: "mitm/peers.json", logical: "peers", envelope: "jsonl.v1"}
        {rel: "mitm/startup.v1.json", logical: "startup", envelope: "jsonl.v1"}
        {rel: "mitm/connect-errors.v1.jsonl", logical: "connect-errors", envelope: "event-stream.v1"}
    ]
    for f in $fixed {
        let abs_p = ($abs_base | path join $f.rel)
        if not ($abs_p | path exists) { continue }
        mut item = (make-item $abs_base $f.rel $f.logical $f.envelope "mitm")
        if $f.envelope == "event-stream.v1" {
            $item = ($item | insert record_count (count-jsonl-records $abs_p))
        }
        $items = ($items | append $item)
    }

    let rpt_json_abs = (try {
        glob ($abs_base | path join "mitm/reports/*.json")
    } catch { [] })
    for p in $rpt_json_abs {
        let fname = ($p | path basename)
        let stem = ($p | path parse | get stem)
        let rel = $"mitm/reports/($fname)"
        $items = ($items | append (make-item $abs_base $rel $stem "jsonl.v1" "mitm"))
    }

    let rpt_tsv_abs = (try {
        glob ($abs_base | path join "mitm/reports/*.tsv")
    } catch { [] })
    for p in $rpt_tsv_abs {
        let fname = ($p | path basename)
        let rel = $"mitm/reports/($fname)"
        $items = ($items | append (
            (make-item $abs_base $rel $fname "text-log.v1" "mitm") | insert language "tsv"
        ))
    }

    $items
}

export def emit-evidence [
    artifacts_base: string,
    cell_id: string,
    run_id: string,
] {
    let abs_base = ($artifacts_base | path expand)

    mut items = []

    let meta_items = (try { collect-meta-items $abs_base } catch {|e|
        print --stderr $"WARNING: meta evidence collection failed: ($e.msg)"
        []
    })
    $items = ($items | append $meta_items)

    let stack_items = (try { collect-stack-items $abs_base } catch {|e|
        print --stderr $"WARNING: stack evidence collection failed: ($e.msg)"
        []
    })
    $items = ($items | append $stack_items)

    let logs_items = (try { collect-logs-items $abs_base } catch {|e|
        print --stderr $"WARNING: logs evidence collection failed: ($e.msg)"
        []
    })
    $items = ($items | append $logs_items)

    let mitm_items = (try { collect-mitm-items $abs_base } catch {|e|
        print --stderr $"WARNING: mitm evidence collection failed: ($e.msg)"
        []
    })
    $items = ($items | append $mitm_items)

    let items = ($items
        | where {|it| ($abs_base | path join $it.path) | path exists}
        | sort-by path)

    let out = {
        schema_version: 1,
        captured_at: (utc-now),
        cell_id: $cell_id,
        run_id: $run_id,
        items: $items,
    }

    let meta_dir = ($abs_base | path join "meta")
    mkdir $meta_dir
    $out | to json --indent 2 | save --force ($meta_dir | path join "evidence.v1.json")
}
