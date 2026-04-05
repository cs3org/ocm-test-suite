# Site ingest helpers: manifest aggregation, artifact copy, and build runner.
# See /temp/ocm-web-site-observatory-contract-v1.md for the data contract.

use ./cell.nu [compute-cell]

def now-utc [] {
    date now | date to-timezone "UTC" | format date "%Y-%m-%dT%H:%M:%SZ"
}

# True when a relative artifact path falls inside the publish allowlist.
def evidence-path-allowed [rel: string] {
    (($rel | str starts-with "meta/")
        or ($rel | str starts-with "docker/logs/")
        or ($rel | str starts-with "cypress/videos/")
        or ($rel | str starts-with "cypress/screenshots/")
        or ($rel == "mitm/peers.json")
        or ($rel | str starts-with "mitm/flows/")
        or ($rel == "mitm/redaction-report.json")
        or ($rel | str starts-with "mitm/reports/"))
}

# Build a flat cell list from matrix-rules.nuon.
# Mirrors `matrix list --json`: one row per
# (scenario, sender_version, receiver_version, browser) for two-party,
# or (scenario, sender_version, browser) for one-party. Includes disabled
# scenarios (placeholder universe). Does NOT call assert-scenario-enabled.
def compute-matrix-cells [rules: record] {
    $rules.scenarios | items {|scenario, sc|
        let recv_platform = ($sc.receiver?.platform? | default "")
        let recv_versions = if ($sc.receiver? != null) {
            $sc.receiver.version_lines
        } else {
            [""]
        }
        let flow_id_arg = ($sc.flow_id? | default $scenario)
        $recv_versions | each {|recv_ver|
            $sc.sender.version_lines | each {|ver|
                $sc.browsers | each {|browser|
                    let cell = (try {
                        (compute-cell $scenario $sc.sender.platform $ver $browser
                            $recv_platform $recv_ver $flow_id_arg)
                    } catch {|e|
                        print $"WARNING: compute-cell failed for ($scenario)/($ver)/($browser): ($e.msg)"
                        null
                    })
                    if $cell != null {
                        $cell | merge {
                            enabled: ($sc.enabled? | default false),
                            mitm: ($sc.mitm? | default false),
                        }
                    }
                } | where {|x| $x != null}
            } | flatten
        } | flatten
    } | flatten
}

# Build matrix-rules.v1.json content (placeholder universe for the UI).
def build-matrix-rules-json [rules: record, rules_path: string] {
    let cell_list = (compute-matrix-cells $rules)
    {
        schema_version: 1,
        generated_at: (now-utc),
        source: $rules_path,
        scenarios: ($cell_list | each {|c| {
            scenario: $c.scenario,
            flow_id: $c.flow_id,
            enabled: $c.enabled,
            browser: $c.browser,
            sender_platform: $c.sender_platform,
            sender_version: $c.sender_version,
            receiver_platform: $c.receiver_platform,
            receiver_version: $c.receiver_version,
            mitm: $c.mitm,
            cell_id: $c.cell_id,
            artifact_name: $c.artifact_name,
        }}),
    }
}

# From a list of per-run ingest entries, keep only the latest per cell_id.
# Tie-break: lexicographic max result_id.
# Entry shape: {manifest, run_dir, artifact_name, exec_id, cell_id, result_id, finished_at}
def pick-latest-per-cell [entries: list] {
    if ($entries | is-empty) { return [] }
    let by_cell = ($entries | group-by cell_id)
    $by_cell | items {|_cell_id, group|
        let sorted = ($group | sort-by finished_at)
        let max_time = ($sorted | last).finished_at
        let candidates = ($sorted | where finished_at == $max_time)
        $candidates | sort-by result_id | last
    }
}

# Recompute latest_terminal_result_by_cell from an aggregated results record.
def compute-latest-index [results: record] {
    if ($results | is-empty) { return {} }
    let rows = ($results | transpose result_id result_val)
    let by_cell = ($rows | group-by {|r| $r.result_val.cell_id? | default ""})
    let pairs = ($by_cell | items {|cell_id, group|
        if ($cell_id | is-empty) { return null }
        let sorted = ($group | sort-by {|r| $r.result_val.finished_at? | default ""})
        let max_time = ($sorted | last).result_val.finished_at? | default ""
        let cands = ($sorted | where {|r| ($r.result_val.finished_at? | default "") == $max_time})
        let best = ($cands | sort-by result_id | last)
        {($cell_id): $best.result_id}
    } | where {|x| $x != null})
    if ($pairs | is-empty) { return {} }
    $pairs | into record
}

# Merge per-run entries into a single aggregated suite-manifest.v1.json.
# Injects run.execution_context from top-level per-run execution_context.
# Filters evidence[] to allowlisted paths only.
def build-aggregated-manifest [entries: list] {
    let selected = (pick-latest-per-cell $entries)
    mut flows = {}
    mut cells = {}
    mut runs = {}
    mut results = {}
    for entry in $selected {
        let m = $entry.manifest
        $flows = ($flows | merge $m.flows)
        $cells = ($cells | merge $m.cells)
        # Inject per-run execution_context into the run map entry.
        let run_id = ($m.runs | columns | first)
        let run_entry = ($m.runs | get $run_id
            | upsert execution_context $m.execution_context)
        $runs = ($runs | upsert $run_id $run_entry)
        # Filter evidence to allowlisted paths only (no download, no compose).
        let result_id = ($m.results | columns | first)
        let raw_res = ($m.results | get $result_id)
        let ev_filtered = ($raw_res.evidence? | default []
            | where {|ev| evidence-path-allowed ($ev.path? | default "")})
        $results = ($results | upsert $result_id ($raw_res | upsert evidence $ev_filtered))
    }
    {
        schema_version: 1,
        generated_at: (now-utc),
        producer: {name: "ocmts", version: "0.1.0"},
        execution_context: {},
        flows: $flows,
        cells: $cells,
        runs: $runs,
        results: $results,
        indexes: {
            latest_terminal_result_by_cell: (compute-latest-index $results),
        },
    }
}

# Copy allowlisted artifact files from src_dir into dst_dir.
# Returns the number of files copied.
export def copy-allowlisted-artifacts [src_dir: string, dst_dir: string] {
    let src = ($src_dir | path expand)
    let all_files = (try {
        glob $"($src)/**/*"
        | where {|p| ($p | path type) == "file"}
    } catch { [] })
    let allowed = ($all_files | where {|p|
        let rel = ($p | path relative-to $src)
        evidence-path-allowed $rel
    })
    for f in $allowed {
        let rel = ($f | path relative-to $src)
        let dst = ($dst_dir | path join $rel)
        mkdir ($dst | path dirname)
        cp $f $dst
    }
    ($allowed | length)
}

# Main ingest: read LAST_EXECUTION_ID for each known cell, aggregate manifests,
# write suite-manifest.v1.json and matrix-rules.v1.json, copy artifacts.
export def ingest-site [
    artifacts_root: string,    # e.g. <ots-root>/artifacts
    matrix_rules_path: string, # e.g. <ots-root>/config/matrix-rules.nuon
    public_dir: string,        # e.g. <site-dir>/public
] {
    let rules = (open $matrix_rules_path)
    let cell_list = (compute-matrix-cells $rules)
    mut entries = []
    for cell in $cell_list {
        let marker = ($artifacts_root | path join $cell.artifact_name "LAST_EXECUTION_ID")
        if not ($marker | path exists) { continue }
        let exec_id = (open --raw $marker | str trim)
        let run_dir = ($artifacts_root | path join $cell.artifact_name $exec_id)
        let mf_path = ($run_dir | path join "meta/suite-manifest.v1.json")
        if not ($mf_path | path exists) {
            print $"WARNING: no suite-manifest for ($cell.artifact_name)/($exec_id), skipping"
            continue
        }
        let m = (open $mf_path)
        let result_id = ($m.results | columns | first)
        let finished_at = ($m.results | get $result_id | get finished_at? | default "")
        $entries = ($entries | append {
            manifest: $m,
            run_dir: $run_dir,
            artifact_name: $cell.artifact_name,
            exec_id: $exec_id,
            cell_id: $cell.cell_id,
            result_id: $result_id,
            finished_at: $finished_at,
        })
    }

    mkdir $public_dir

    let aggregated = (build-aggregated-manifest $entries)
    ($aggregated | to json --indent 2
        | save --force ($public_dir | path join "suite-manifest.v1.json"))
    print $"Wrote suite-manifest.v1.json \(($entries | length) runs\)"

    let matrix_json = (build-matrix-rules-json $rules $matrix_rules_path)
    ($matrix_json | to json --indent 2
        | save --force ($public_dir | path join "matrix-rules.v1.json"))
    print $"Wrote matrix-rules.v1.json \(($matrix_json.scenarios | length) scenarios\)"

    mut total_files = 0
    for entry in $entries {
        let dst_base = ($public_dir
            | path join "artifacts" $entry.artifact_name $entry.exec_id)
        let count = (copy-allowlisted-artifacts $entry.run_dir $dst_base)
        print $"  ($entry.artifact_name)/($entry.exec_id): ($count) files"
        $total_files = $total_files + $count
    }
    print $"Ingest complete: ($entries | length) runs, ($total_files) artifact files"
}

# Run the Astro site build command, preferring bun over npm.
# Streams build output to the terminal (no capture).
export def run-site-build [site_dir: string] {
    let bun_ok = (try {
        (^bun --version | complete).exit_code == 0
    } catch { false })
    let cmd = if $bun_ok { "bun" } else { "npm" }
    print $"Building with ($cmd) in ($site_dir)..."
    cd $site_dir
    if $bun_ok {
        ^bun run build
    } else {
        ^npm run build
    }
    if $env.LAST_EXIT_CODE != 0 {
        error make {msg: "Site build failed. See output above."}
    }
}
