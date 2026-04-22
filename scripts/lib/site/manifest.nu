# Manifest aggregation: matrix-rules JSON, image provenance, and suite manifest.

use ./internal.nu [now-utc evidence-path-allowed compute-matrix-cells]

# Build matrix-rules.v1.json content (placeholder universe for the UI).
export def build-matrix-rules-json [rules: record, rules_path: string] {
    let cell_list = (compute-matrix-cells $rules)
    {
        schema_version: 1,
        generated_at: (now-utc),
        source: $rules_path,
        scenarios: ($cell_list | each {|c| {
            scenario: $c.scenario,
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
        }}),
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

# Best-effort docker image inspect for one ref.
# Returns {local_image_id, repo_digests} or null on any failure.
export def inspect-one-image [ref: string] {
    if ($ref | is-empty) { return null }
    let result = (try {
        ^docker image inspect $ref | complete
    } catch {
        {exit_code: 127, stdout: "", stderr: ""}
    })
    if $result.exit_code != 0 { return null }
    let parsed = (try { $result.stdout | from json } catch { return null })
    if ($parsed | is-empty) { return null }
    let info = ($parsed | first)
    {
        local_image_id: ($info.Id? | default null),
        repo_digests: ($info.RepoDigests? | default []),
    }
}

# For each image ref in the images record, attempt docker inspect.
# Returns a record with the same keys; per-entry value is provenance or null.
export def build-images-provenance [images: record] {
    if ($images | is-empty) { return {} }
    $images | transpose key ref | each {|row|
        let prov = (try {
            inspect-one-image ($row.ref | into string)
        } catch { null })
        {($row.key): $prov}
    } | into record
}

# Stable sha256 of sorted file contents under compose/inputs/.
# Returns null if the inputs dir is absent or empty.
export def compute-stack-def-sha256 [run_dir: string] {
    let inputs_dir = ($run_dir | path join "compose/inputs")
    if not ($inputs_dir | path exists) { return null }
    let files = (try {
        glob $"($inputs_dir)/*"
        | where {|p| ($p | path type) == "file"}
        | sort
    } catch { return null })
    if ($files | is-empty) { return null }
    let combined = ($files | each {|f|
        try { open --raw $f } catch { "" }
    } | str join "")
    $combined | hash sha256
}

# Merge per-run entries into a single aggregated suite-manifest.v1.json.
# Injects run.execution_context from top-level per-run execution_context.
# Filters evidence[] to allowlisted paths only.
export def build-aggregated-manifest [entries: list] {
    let selected = (pick-latest-per-cell $entries)
    mut flows = {}
    mut cells = {}
    mut runs = {}
    mut results = {}
    for entry in $selected {
        let m = $entry.manifest
        $flows = ($flows | merge $m.flows)
        $cells = ($cells | merge $m.cells)
        # Inject per-run execution_context and resolved image pins into run map.
        let run_id = ($m.runs | columns | first)
        let run_json_path = ($entry.run_dir | path join "meta/run.json")
        let run_images = if ($run_json_path | path exists) {
            (open $run_json_path).images? | default {}
        } else {
            {}
        }
        let run_provenance = (build-images-provenance $run_images)
        let stack_hash = (compute-stack-def-sha256 $entry.run_dir)
        let run_entry = ($m.runs | get $run_id
            | upsert execution_context $m.execution_context
            | upsert images $run_images
            | upsert images_provenance $run_provenance
            | upsert stack_def_sha256 $stack_hash)
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
