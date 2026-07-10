# Manifest aggregation: matrix-rules JSON and suite manifest.

use ./internal.nu [evidence-path-allowed compute-matrix-cells]
use ./provenance.nu [build-provenance-block SITE_PROVENANCE_SOURCES]
use ../matrix/rules-gen.nu [apply-display-rule]

# Build matrix-rules.v1.json content.
# Cells are filtered through apply-display-rule: vendor-out-of-scope cells
# are excluded and each kept cell carries a display_status enum value.
export def build-matrix-rules-json [
    rules: record,
    rules_path: string,
    adapters: record,
    flow_caps: record,
    ocmts_root: string,
] {
    let cell_list = (compute-matrix-cells $rules)
    let result = (apply-display-rule $cell_list $adapters $flow_caps)

    let required_flow_fields = ["flow_id" "label" "subtitle" "glyph_id" "display_order" "enabled" "two_party" "mitm"]
    let flows_dir = ($ocmts_root | path join "config/matrix/flows")
    let flow_files = (glob ($flows_dir | path join "*.nuon") | sort)
    if ($flow_files | is-empty) {
        error make {msg: $"build-matrix-rules-json: no flow files found under ($flows_dir) -- expected at least one *.nuon"}
    }
    let flows_out = ($flow_files | each {|f|
        let raw = open $f
        let missing = ($required_flow_fields | where {|field| ($raw | get --optional $field) == null})
        if not ($missing | is-empty) {
            error make {msg: $"flow file '($f)' missing required fields: ($missing | str join ', ')"}
        }
        let glyph_id = ($raw.glyph_id? | default "")
        if ($glyph_id | describe) != "string" or (($glyph_id | str trim) | is-empty) {
            error make {msg: $"flow file '($f)' has invalid glyph_id: must be a non-empty non-whitespace string"}
        }
        $raw | select flow_id label subtitle glyph_id display_order enabled two_party mitm
    } | sort-by display_order flow_id)

    let platforms_data = open ($ocmts_root | path join "config/matrix/platforms.nuon")
    let platforms_raw = $platforms_data.platforms?
    if ($platforms_raw == null) or ($platforms_raw | is-empty) {
        error make {msg: $"build-matrix-rules-json: ($rules_path) has no 'platforms' record or it is empty"}
    }
    let required_platform_fields = ["display_name" "version_lines"]
    mut platforms_out = []
    for row in ($platforms_raw | transpose id platform_data) {
        let pid = $row.id
        let p = $row.platform_data
        let missing = ($required_platform_fields | where {|k| not ($k in $p) })
        if not ($missing | is-empty) {
            error make {msg: $"build-matrix-rules-json: ($rules_path) platform '($pid)' is missing required keys: ($missing | str join ', ')"}
        }
        let vl = $p.version_lines
        if (($vl | describe) !~ '^(list|table)') or (($vl | length) == 0) {
            error make {msg: $"build-matrix-rules-json: ($rules_path) platform '($pid)' version_lines must be a non-empty list"}
        }
        $platforms_out = ($platforms_out | append {
            id: $pid,
            display_name: $p.display_name,
            version_lines: $p.version_lines,
        })
    }
    let platforms_out = ($platforms_out | sort-by display_name id)

    let prov = (build-provenance-block {
        generator: "scripts/lib/site/manifest.nu#build-matrix-rules-json",
        producer: {name: "ocmts", version: "0.1.0"},
        sources: $SITE_PROVENANCE_SOURCES,
        ocmts_root: $ocmts_root,
    })
    $prov | merge {
        source: $rules_path,
        flows: $flows_out,
        platforms: $platforms_out,
        matrix: ($result.kept_cells | each {|c|
            mut out = {
                matrix_key: $c.matrix_key,
                flow_id: $c.flow_id,
                pair: $c.pair,
                enabled: $c.enabled,
                browser: $c.browser,
                sender_platform: $c.sender_platform,
                sender_version: $c.sender_version,
                receiver_platform: $c.receiver_platform,
                receiver_version: $c.receiver_version,
                mitm: $c.mitm,
                cell_id: $c.cell_id,
                artifact_name: $c.artifact_name,
                display_status: $c.display_status,
            }
            let tu = ($c.tracking_url? | default null)
            let tn = ($c.tracking_note? | default null)
            let rt = ($c.rationale? | default null)
            if $tu != null { $out = ($out | upsert tracking_url $tu) }
            if $tn != null { $out = ($out | upsert tracking_note $tn) }
            if $rt != null { $out = ($out | upsert rationale $rt) }
            $out
        }),
    }
}

# From a list of per-run ingest entries, keep only the latest per cell_id.
# Tie-break: lexicographic max result_id.
# Entry shape: {manifest, run_dir, artifact_name, exec_id, cell_id, result_id, finished_at}
export def pick-latest-per-cell [entries: list] {
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
export def compute-latest-index [results: record] {
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
export def build-aggregated-manifest [entries: list, ocmts_root: string] {
    let selected = (pick-latest-per-cell $entries)
    mut flows = {}
    mut cells = {}
    mut runs = {}
    mut results = {}
    for entry in $selected {
        let m = $entry.manifest
        $flows = ($flows | merge $m.flows)
        $cells = ($cells | merge $m.cells)
        # Inject per-run execution_context into run map.
        let run_id = ($m.runs | columns | first)
        let run_entry = ($m.runs | get $run_id
            | upsert execution_context $m.execution_context)
        $runs = ($runs | upsert $run_id $run_entry)
        # Filter evidence to allowlisted paths only.
        let result_id = ($m.results | columns | first)
        let raw_res = ($m.results | get $result_id)
        let ev_filtered = ($raw_res.evidence? | default []
            | where {|ev| evidence-path-allowed ($ev.path? | default "")})
        $results = ($results | upsert $result_id ($raw_res | upsert evidence $ev_filtered))
    }
    # Aggregator has no fixed input files; per-run execution_context is injected above.
    let prov = (build-provenance-block {
        generator: "scripts/lib/site/manifest.nu#build-aggregated-manifest",
        producer: {name: "ocmts", version: "0.1.0"},
        sources: [],
        ocmts_root: $ocmts_root,
    })
    $prov | merge {
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
