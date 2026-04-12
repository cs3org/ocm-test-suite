# Site ingest helpers: manifest aggregation, artifact copy, and build runner.
# See /temp/ocm-web-site-observatory-contract-v1.md for the data contract.

use ./cell.nu [compute-cell]
use ./matrix-expand.nu [expand-version-pairs]
use ./suite-index.nu [load-suite-entry]

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
#
# Intentionally best-effort: each compute-cell call is wrapped in try/catch.
# On failure the row is warned and dropped (null-filtered). This differs from
# expand-matrix-cells (matrix-cells.nu) which fails hard on any cell error.
# Site ingest favors a partial result over a complete abort.
def compute-matrix-cells [rules: record] {
    $rules.scenarios | items {|scenario, sc|
        let recv_platform = ($sc.receiver?.platform? | default "")
        let flow_id_arg = ($sc.flow_id? | default $scenario)
        let version_pairs = (expand-version-pairs $sc)
        $version_pairs | each {|vp|
            $sc.browsers | each {|browser|
                let cell = (try {
                    (compute-cell $scenario $sc.sender.platform $vp.sender_version $browser
                        $recv_platform $vp.receiver_version $flow_id_arg)
                } catch {|e|
                    print $"WARNING: compute-cell failed for ($scenario)/($vp.sender_version)/($browser): ($e.msg)"
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
}

# Derive requirements and blockers for one cell against the adapter capability
# map. Returns {requirements: list, blockers: list}.
def derive-cell-impl-info [cell: record, adapters: record] {
    let flow_id = $cell.flow_id
    let sender_key = $"($cell.sender_platform)/($cell.sender_version)"

    let flow_sender_caps = if $flow_id == "login" {
        ["login"]
    } else if $flow_id in ["share-with", "contact-wayf", "contact-token"] {
        ["login", "share-with.sender"]
    } else {
        null
    }

    if $flow_sender_caps == null {
        return {
            requirements: [],
            blockers: [{reason_code: "unknown_flow_id", flow_id: $flow_id, role: "", adapter_key: "", capability: ""}],
        }
    }

    mut requirements = []
    mut blockers = []

    if $sender_key in $adapters {
        let sender_caps = ($adapters | get $sender_key)
        for cap in $flow_sender_caps {
            $requirements = ($requirements | append {capability: $cap, role: "sender", adapter_key: $sender_key})
            if not ($cap in $sender_caps) {
                $blockers = ($blockers | append {reason_code: "missing_capability", role: "sender", adapter_key: $sender_key, capability: $cap})
            }
        }
    } else {
        for cap in $flow_sender_caps {
            $requirements = ($requirements | append {capability: $cap, role: "sender", adapter_key: $sender_key})
        }
        $blockers = ($blockers | append {reason_code: "missing_adapter_bundle", role: "sender", adapter_key: $sender_key, capability: ""})
    }

    if $cell.is_two_party {
        let receiver_key = $"($cell.receiver_platform)/($cell.receiver_version)"
        let flow_receiver_caps = if $flow_id in ["share-with", "contact-wayf", "contact-token"] {
            ["login", "share-with.receiver"]
        } else {
            []
        }
        if not ($flow_receiver_caps | is-empty) {
            if $receiver_key in $adapters {
                let receiver_caps = ($adapters | get $receiver_key)
                for cap in $flow_receiver_caps {
                    $requirements = ($requirements | append {capability: $cap, role: "receiver", adapter_key: $receiver_key})
                    if not ($cap in $receiver_caps) {
                        $blockers = ($blockers | append {reason_code: "missing_capability", role: "receiver", adapter_key: $receiver_key, capability: $cap})
                    }
                }
            } else {
                for cap in $flow_receiver_caps {
                    $requirements = ($requirements | append {capability: $cap, role: "receiver", adapter_key: $receiver_key})
                }
                $blockers = ($blockers | append {reason_code: "missing_adapter_bundle", role: "receiver", adapter_key: $receiver_key, capability: ""})
            }
        }
    }

    {requirements: $requirements, blockers: $blockers}
}

# Build implemented-cells.v1.json content.
# Evaluates each matrix cell (including disabled) against the adapter
# capability map and produces a structured record keyed by cell_id.
def build-implemented-cells-json [rules: record, rules_path: string, cap_map_path: string] {
    let cap_map = (open $cap_map_path)
    let adapters = ($cap_map.adapters? | default {})
    let cell_list = (compute-matrix-cells $rules)
    let cells = if ($cell_list | is-empty) {
        {}
    } else {
        ($cell_list | each {|c|
            let impl_info = (derive-cell-impl-info $c $adapters)
            {
                ($c.cell_id): {
                    scenario: $c.scenario,
                    flow_id: $c.flow_id,
                    pair: $c.pair,
                    browser: $c.browser,
                    sender_platform: $c.sender_platform,
                    sender_version: $c.sender_version,
                    receiver_platform: $c.receiver_platform,
                    receiver_version: $c.receiver_version,
                    artifact_name: $c.artifact_name,
                    mitm: $c.mitm,
                    implemented: ($impl_info.blockers | is-empty),
                    requirements: $impl_info.requirements,
                    blockers: $impl_info.blockers,
                }
            }
        } | into record)
    }
    {
        schema_version: 1,
        generated_at: (now-utc),
        sources: {
            matrix_rules_path: $rules_path,
            capability_map_path: $cap_map_path,
        },
        cells: $cells,
    }
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

# Best-effort docker image inspect for one ref.
# Returns {local_image_id, repo_digests} or null on any failure.
def inspect-one-image [ref: string] {
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
def build-images-provenance [images: record] {
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
def compute-stack-def-sha256 [run_dir: string] {
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

# Main ingest: aggregate manifests, write suite-manifest.v1.json and
# matrix-rules.v1.json, copy artifacts.
# Default: reads LAST_EXECUTION_ID per cell. With --suite-id or --latest-suite,
# reads the suite index and ingests exactly the runs listed there.
export def ingest-site [
    artifacts_root: string,    # e.g. <ocmts-root>/artifacts
    matrix_rules_path: string, # e.g. <ocmts-root>/config/matrix-rules.nuon
    public_dir: string,        # e.g. <site-dir>/public
    --suite-id: string = "",   # ingest runs from this suite_id only
    --latest-suite,            # ingest runs from the latest suite (LATEST_SUITE_ID)
] {
    let rules = (open $matrix_rules_path)
    let cell_list = (compute-matrix-cells $rules)
    let suite_active = (not ($suite_id | is-empty)) or $latest_suite
    mut entries = []
    if $suite_active {
        let loaded = (load-suite-entry $artifacts_root $suite_id $latest_suite)
        let eff_id = $loaded.suite_id
        let suite_record = $loaded.suite_record
        let run_count = ($suite_record.runs | length)
        print $"Ingest mode: suite suite_id=($eff_id) runs=($run_count)"
        for run in $suite_record.runs {
            let run_dir = ($artifacts_root | path join $run.flow_id $run.pair $run.execution_id)
            let mf_path = ($run_dir | path join "meta/suite-manifest.v1.json")
            if not ($mf_path | path exists) {
                print $"WARNING: no suite-manifest for ($run.flow_id)/($run.pair)/($run.execution_id), skipping"
                continue
            }
            let m = (open $mf_path)
            let result_id = ($m.results | columns | first)
            let finished_at = ($m.results | get $result_id | get finished_at? | default "")
            $entries = ($entries | append {
                manifest: $m,
                run_dir: $run_dir,
                flow_id: $run.flow_id,
                pair: $run.pair,
                artifact_name: ($run.artifact_name? | default ""),
                exec_id: $run.execution_id,
                cell_id: $run.cell_id,
                result_id: $result_id,
                finished_at: $finished_at,
            })
        }
    } else {
        for cell in $cell_list {
            let marker = ($artifacts_root | path join $cell.flow_id $cell.pair "LAST_EXECUTION_ID")
            if not ($marker | path exists) { continue }
            let exec_id = (open --raw $marker | str trim)
            let run_dir = ($artifacts_root | path join $cell.flow_id $cell.pair $exec_id)
            let mf_path = ($run_dir | path join "meta/suite-manifest.v1.json")
            if not ($mf_path | path exists) {
                print $"WARNING: no suite-manifest for ($cell.flow_id)/($cell.pair)/($exec_id), skipping"
                continue
            }
            let m = (open $mf_path)
            let result_id = ($m.results | columns | first)
            let finished_at = ($m.results | get $result_id | get finished_at? | default "")
            $entries = ($entries | append {
                manifest: $m,
                run_dir: $run_dir,
                flow_id: $cell.flow_id,
                pair: $cell.pair,
                artifact_name: $cell.artifact_name,
                exec_id: $exec_id,
                cell_id: $cell.cell_id,
                result_id: $result_id,
                finished_at: $finished_at,
            })
        }
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

    let ots_root = ($matrix_rules_path | path expand | path dirname | path dirname)
    let cap_map_path = ($ots_root | path join "cypress/support/adapters/adapter-capabilities.v1.json")
    if ($cap_map_path | path exists) {
        let impl_cells_json = (build-implemented-cells-json $rules $matrix_rules_path $cap_map_path)
        ($impl_cells_json | to json --indent 2
            | save --force ($public_dir | path join "implemented-cells.v1.json"))
        print $"Wrote implemented-cells.v1.json \(($impl_cells_json.cells | columns | length) cells\)"
    } else {
        print $"WARNING: capability map not found at ($cap_map_path), skipping implemented-cells.v1.json"
    }

    mut total_files = 0
    for entry in $entries {
        let dst_base = ($public_dir
            | path join "artifacts" $entry.flow_id $entry.pair $entry.exec_id)
        let count = (copy-allowlisted-artifacts $entry.run_dir $dst_base)
        print $"  ($entry.flow_id)/($entry.pair)/($entry.exec_id): ($count) files"
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
