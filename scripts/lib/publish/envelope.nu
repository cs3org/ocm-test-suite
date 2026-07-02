# Emit publish envelope after a terminal run.
# Writes meta/suite-manifest.v1.json.
# Prompt 6 SSOT: stable IDs, observed state, mandatory execution_context,
# evidence rows on result, indexes. Banned fields: backend, executor,
# provenance, trust, publication_state, published_at.

use ../run/tuple-identity.nu [load-meta-identity]
use ../run/flow-ids.nu [PUBLIC_FLOW_IDS]
use ../time/utc.nu [utc-now]

def flow-description [flow_id: string] {
    match $flow_id {
        "login" => "OCM login flow"
        "share-with" => "OCM share-with flow"
        "contact-token" => "OCM contact-token flow"
        "contact-wayf" => "OCM contact-wayf flow"
        _ => $"OCM ($flow_id) flow"
    }
}

def build-github-env [] {
    mut gh = {}
    let run_id = ($env.GITHUB_RUN_ID? | default "")
    let run_attempt = ($env.GITHUB_RUN_ATTEMPT? | default "")
    let workflow = ($env.GITHUB_WORKFLOW? | default "")
    let job = ($env.GITHUB_JOB? | default "")
    let sha = ($env.GITHUB_SHA? | default "")
    let ref_val = ($env.GITHUB_REF? | default "")
    let repository = ($env.GITHUB_REPOSITORY? | default "")
    let actor = ($env.GITHUB_ACTOR? | default "")
    let event_name = ($env.GITHUB_EVENT_NAME? | default "")
    if not ($run_id | is-empty) { $gh = ($gh | upsert run_id $run_id) }
    if not ($run_attempt | is-empty) { $gh = ($gh | upsert run_attempt $run_attempt) }
    if not ($workflow | is-empty) { $gh = ($gh | upsert workflow $workflow) }
    if not ($job | is-empty) { $gh = ($gh | upsert job $job) }
    if not ($sha | is-empty) { $gh = ($gh | upsert sha $sha) }
    if not ($ref_val | is-empty) { $gh = ($gh | upsert ref $ref_val) }
    if not ($repository | is-empty) { $gh = ($gh | upsert repository $repository) }
    if not ($actor | is-empty) { $gh = ($gh | upsert actor $actor) }
    if not ($event_name | is-empty) { $gh = ($gh | upsert event_name $event_name) }
    $gh
}

export def detect-execution-context [] {
    # ACT takes priority; GITHUB_ACTIONS signals real CI; else local.
    #
    # Detect act via ACT=true (case-insensitive). Treat other non-empty values
    # as not-act to avoid surprising mis-detection.
    let act_val = (($env.ACT? | default "") | str downcase | str trim)
    let gha_val = (($env.GITHUB_ACTIONS? | default "") | str downcase | str trim)
    let is_act = ($act_val == "true")
    let is_gha = ($gha_val == "true")
    if $is_act {
        {kind: "github-actions-act", is_ci: true, is_act: true, github: (build-github-env)}
    } else if $is_gha {
        {kind: "github-actions", is_ci: true, is_act: false, github: (build-github-env)}
    } else {
        {kind: "local-shell", is_ci: false, is_act: false, github: {}}
    }
}

# Compute a stable evidence_id slug from a relative artifact path.
# Strips the file extension and replaces path separators with --.
export def path-to-evidence-id [rel: string] {
    let p = ($rel | path parse)
    let no_ext = if ($p.parent | is-empty) {
        $p.stem
    } else {
        ($p.parent | path join $p.stem)
    }
    $no_ext | str replace --all "/" "--"
}

# Parse a screenshot filename stem in <cell_id>--<NNN>--<actor>--<checkpoint> shape.
# Returns null when the stem does not match the convention.
export def parse-screenshot-stem [stem: string] {
    let m = ($stem | parse --regex '^(?P<cell_id>.+)--(?P<order>\d{3})--(?P<actor>single|sender|receiver)--(?P<checkpoint>.+)$')
    if ($m | is-empty) { return null }
    let r = ($m | first)
    {cell_id: $r.cell_id, order: ($r.order | into int), actor: $r.actor, checkpoint: $r.checkpoint}
}

# Parse a video filename stem in <cell_id>--run shape.
# Returns null when the stem does not follow the convention.
export def parse-video-stem [stem: string] {
    let m = ($stem | parse --regex '^(?P<cell_id>.+)--run$')
    if ($m | is-empty) { return null }
    let cell_id = ($m | first | get cell_id)
    if ($cell_id | is-empty) { return null }
    {cell_id: $cell_id}
}

# Enrich one evidence row with evidence_id and classification fields.
# Screenshots: capture_class proof|failure-auto; order/actor/checkpoint/cell_id when parseable.
# Videos: capture_class run|legacy; cell_id from filename or manifest fallback.
# Other kinds: evidence_id only.
# manifest_cell_id is the fallback cell_id from the run manifest (meta/cell.json).
export def enrich-ev-row [row: record, manifest_cell_id: string] {
    let ev_id = (path-to-evidence-id $row.path)
    let base = ($row | upsert evidence_id $ev_id)
    if $row.kind == "screenshot" {
        let stem = (($row.logical_name | path parse) | get stem)
        let parsed = (parse-screenshot-stem $stem)
        if $parsed != null {
            let cid = if ($parsed.cell_id | is-empty) { $manifest_cell_id } else { $parsed.cell_id }
            ($base
                | upsert capture_class "proof"
                | upsert order $parsed.order
                | upsert actor $parsed.actor
                | upsert checkpoint $parsed.checkpoint
                | upsert cell_id $cid)
        } else {
            ($base
                | upsert capture_class "failure-auto"
                | upsert cell_id $manifest_cell_id)
        }
    } else if $row.kind == "video" {
        let stem = (($row.logical_name | path parse) | get stem)
        let parsed = (parse-video-stem $stem)
        if $parsed != null {
            ($base
                | upsert capture_class "run"
                | upsert cell_id $parsed.cell_id)
        } else {
            ($base
                | upsert capture_class "legacy"
                | upsert cell_id $manifest_cell_id)
        }
    } else {
        $base
    }
}

# Sort enriched evidence rows for stable, human-friendly gallery ordering.
# Kind order: metadata < log < screenshot < video < download < mitm-flow < mitm-report.
# Within screenshots: by cell_id then parsed order ascending, then path.
# Rows without an order field sort after those with one; all ties break by path.
export def sort-evidence-rows []: list -> list {
    let kind_rank = {
        metadata: 0, log: 1, screenshot: 2, video: 3,
        download: 4, "mitm-flow": 5, "mitm-report": 6,
    }
    $in | sort-by {|r|
        let rank = ($kind_rank | get --optional $r.kind | default 99
            | into string | fill --width 2 --alignment right --character "0")
        let cell = ($r.cell_id? | default "")
        let ord = ($r.order? | default 999999
            | into string | fill --width 9 --alignment right --character "0")
        $"($rank):($cell):($ord):($r.path)"
    }
}

# Classify a relative path into an evidence row.
def path-to-row [rel: string] {
    let kind = (if ($rel | str starts-with "docker/logs/") { "log"
        } else if ($rel | str starts-with "cypress/screenshots/") { "screenshot"
        } else if ($rel | str starts-with "cypress/videos/") { "video"
        } else if ($rel | str starts-with "cypress/downloads/") { "download"
        } else if ($rel | str starts-with "mitm/flows/") { "mitm-flow"
        } else if ($rel | str starts-with "mitm/redaction") { "mitm-report"
        } else if ($rel | str starts-with "mitm/reports/") { "mitm-report"
        } else if ($rel | str starts-with "mitm/") { "mitm-report"
        } else if ($rel | str starts-with "meta/") { "metadata"
        } else if ($rel | str starts-with "compose/") { "metadata"
        } else { "" })
    if ($kind | is-empty) {
        error make {msg: $"Unsupported evidence kind for path: ($rel). Allowed kinds: metadata, log, screenshot, video, download, mitm-flow, mitm-report."}
    }
    let scope = (if ($rel | str starts-with "docker/") { "docker"
        } else if ($rel | str starts-with "cypress/") { "cypress"
        } else if ($rel | str starts-with "mitm/") { "mitm"
        } else if ($rel | str starts-with "meta/") { "meta"
        } else if ($rel | str starts-with "compose/") { "compose"
        } else { "other" })
    {
        kind: $kind,
        scope: $scope,
        logical_name: ($rel | path basename),
        path: $rel,
        availability: "artifact",
    }
}

# Collect evidence rows, MITM presence, and counts.
export def collect-evidence [base: string] {
    let abs_base = ($base | path expand)
    let prefix = $"($abs_base)/"
    mut rels = []

    for rel in [
        "meta/run.json"
        "meta/result.v1.json"
        "meta/cell.json"
        "meta/images.v1.json"
    ] {
        if (($abs_base | path join $rel) | path exists) { $rels = ($rels | append $rel) }
    }

    if (($abs_base | path join "compose/manifest.v1.json") | path exists) {
        $rels = ($rels | append "compose/manifest.v1.json")
    }

    let log_abs = (try { glob ($abs_base | path join "docker/logs/*.log") } catch { [] })
    let log_rel = ($log_abs | each {|p| $p | str replace $prefix ""})
    $rels = ($rels | append $log_rel)

    let ss_abs = (try {
        glob ($abs_base | path join "cypress/screenshots/**/*.png")
    } catch { [] })
    let ss_rel = ($ss_abs | each {|p| $p | str replace $prefix ""})

    let vid_abs = (try {
        glob ($abs_base | path join "cypress/videos/*.mp4")
    } catch { [] })
    let vid_rel = ($vid_abs | each {|p| $p | str replace $prefix ""})

    let dl_abs = (try {
        glob ($abs_base | path join "cypress/downloads/**/*")
        | where {|p| ($p | path type) == "file"}
    } catch { [] })
    let dl_rel = ($dl_abs | each {|p| $p | str replace $prefix ""})

    $rels = ($rels | append $ss_rel | append $vid_rel | append $dl_rel)

    let mitm_candidates = [
        "mitm/flows/traffic.jsonl"
        "mitm/flows/session.json"
        "mitm/redaction-report.json"
        "mitm/reports/01-01-traffic-overview.md"
        "mitm/reports/01-02-traffic-overview.json"
        "mitm/reports/02-01-ocm-endpoints.md"
        "mitm/reports/02-02-ocm-endpoints.json"
        "mitm/reports/03-01-ocm-details.md"
        "mitm/reports/03-02-ocm-details.json"
        "mitm/reports/03-03-ocm-details.tsv"
        "mitm/reports/99-traffic-pretty.json"
        "mitm/peers.json"
        "mitm/startup.v1.json"
        "mitm/connect-errors.v1.jsonl"
    ]
    let mitm_rel = ($mitm_candidates | where {|p|
        ($abs_base | path join $p) | path exists
    })
    $rels = ($rels | append $mitm_rel)

    let rows = ($rels | each {|r| path-to-row $r})

    {
        rows: $rows,
        mitm_present: (not ($mitm_rel | is-empty)),
        counts: {
            total: ($rels | length),
            docker_logs: ($log_rel | length),
            cypress_screenshots: ($ss_rel | length),
            cypress_videos: ($vid_rel | length),
            cypress_downloads: ($dl_rel | length),
            mitm_files: ($mitm_rel | length),
        },
    }
}

# Semantic consistency checks. Returns a list of error strings.
# Cell and flow map entries must have an `id` field; cells must have `flow_id`.
def consistency-errors [manifest: record] {
    let runs = $manifest.runs
    let results = $manifest.results
    let cells = $manifest.cells
    let flows = $manifest.flows
    let idx = (
        $manifest.indexes?
        | default {}
        | get --optional latest_terminal_result_by_cell
        | default {}
    )

    # Map key == embedded id field
    let key_errors = (
        ($runs | transpose k v
            | where {|r| $r.k != $r.v.id}
            | each {|r| $"run key '($r.k)' != run.id '($r.v.id)'"})
        | append ($results | transpose k v
            | where {|r| $r.k != $r.v.id}
            | each {|r| $"result key '($r.k)' != result.id '($r.v.id)'"})
        | append ($cells | transpose k v
            | where {|r| $r.k != ($r.v.id? | default "")}
            | each {|r| $"cell key '($r.k)' != cell.id '($r.v.id?)'"})
        | append ($flows | transpose k v
            | where {|r| $r.k != ($r.v.id? | default "")}
            | each {|r| $"flow key '($r.k)' != flow.id '($r.v.id?)'"})
    )

    # run.cell_id resolves to cells
    let run_cell_errors = ($runs | transpose k v | each {|row|
        let run = $row.v
        let cell_id = ($run.cell_id? | default "")
        if ($cell_id | is-empty) {
            [$"run '($run.id)': missing cell_id"]
        } else if ($cells | get --optional $cell_id) == null {
            [$"run '($run.id)': cell_id '($cell_id)' not in cells"]
        } else {
            []
        }
    } | flatten)

    # Cross-reference checks from each result
    let ref_errors = ($results | transpose k v | each {|row|
        let res = $row.v
        let run_id = ($res.run_id? | default "")
        let cell_id = ($res.cell_id? | default "")
        mut errs = []
        if ($run_id | is-empty) {
            $errs = ($errs | append $"result '($res.id)': missing run_id")
        } else {
            let run_ref = ($runs | get --optional $run_id)
            if $run_ref == null {
                $errs = ($errs | append $"result '($res.id)': run_id '($run_id)' not in runs")
            } else if (($run_ref.cell_id? | default "") != $cell_id) {
                $errs = ($errs | append $"result '($res.id)': cell_id mismatch with run '($run_id)'")
            }
        }
        if ($cell_id | is-empty) {
            $errs = ($errs | append $"result '($res.id)': missing cell_id")
        } else {
            let cell_ref = ($cells | get --optional $cell_id)
            if $cell_ref == null {
                $errs = ($errs | append $"result '($res.id)': cell_id '($cell_id)' not in cells")
            } else {
                let fid = ($cell_ref.flow_id? | default "")
                if ($flows | get --optional $fid) == null {
                    $errs = ($errs | append $"cell '($cell_id)': flow_id '($fid)' not in flows")
                }
                if not ($fid in $PUBLIC_FLOW_IDS) {
                    $errs = ($errs | append $"cell '($cell_id)': flow_id '($fid)' not in public flow id allowlist")
                }
            }
        }
        $errs
    } | flatten)

    # Index integrity
    let idx_errors = ($idx | transpose k v | each {|row|
        let res_ref = ($results | get --optional $row.v)
        if $res_ref == null {
            [$"index: result '($row.v)' for cell '($row.k)' not in results"]
        } else if (($res_ref.cell_id? | default "") != $row.k) {
            [$"index: result '($row.v)' cell_id != indexed key '($row.k)'"]
        } else {
            []
        }
    } | flatten)

    # Completed runs must have exactly one terminal result
    let run_result_errors = ($runs | transpose k v | each {|row|
        let run = $row.v
        if ($run.lifecycle_status? | default "") == "completed" {
            let count = ($results | transpose k v
                | where {|r| ($r.v.run_id? | default "") == $run.id}
                | length)
            if $count != 1 {
                [$"run '($run.id)': completed but has ($count) results \(expected 1\)"]
            } else {
                []
            }
        } else {
            []
        }
    } | flatten)

    ($key_errors | append $run_cell_errors | append $ref_errors | append $idx_errors | append $run_result_errors)
}


# Emit suite-manifest.v1.json into <artifacts_base>/meta/.
# Reads meta/cell.json, meta/run.json, meta/result.v1.json. Throws
# on missing inputs, write failures, or consistency errors (after
# writing outputs for debuggability).
export def emit-publish-envelope [artifacts_base: string] {
    let base = ($artifacts_base | str trim --right --char "/" | path expand)
    let meta_dir = ($base | path join "meta")

    let cell = (open ($meta_dir | path join "cell.json"))
    let run = (open ($meta_dir | path join "run.json"))
    let result = (open ($meta_dir | path join "result.v1.json"))

    let generated_at = (utc-now)
    let ctx = (detect-execution-context)
    let ev = (collect-evidence $base)
    let ev_rows = ($ev.rows | each {|row| enrich-ev-row $row $cell.cell_id} | sort-evidence-rows)

    # Suite grouping fields - optional, backward compatible with legacy runs.
    let suite_id = ($cell.suite_id? | default "")
    let suite_kind = ($cell.suite_kind? | default "")

    # Stable IDs (current proof-slice: run.id == execution_id)
    let run_id = ($run.id? | default $run.execution_id)
    let result_id = ($result.id? | default $"result-($result.execution_id)")
    let result_run_id = ($result.run_id? | default $result.execution_id)

    let identity = (load-meta-identity $base)
    let flow_id = $identity.flow_id
    let flow_entry = {id: $flow_id, description: (flow-description $flow_id)}

    let matrix_key = $identity.matrix_key

    let cell_entry = {
        id: $cell.cell_id,
        flow_id: $flow_id,
        pair: ($cell.pair? | default ""),
        artifact_name: $cell.artifact_name,
        matrix_key: $matrix_key,
        sender_platform: $cell.sender_platform,
        sender_version: $cell.sender_version,
        receiver_platform: ($cell.receiver_platform? | default ""),
        receiver_version: ($cell.receiver_version? | default ""),
        browser: ($cell.browser? | default "chrome"),
        is_two_party: ($cell.is_two_party? | default false),
    }
    # failure_reason must be concrete and observed.
    # Prefer run.error when present; otherwise, fall back to a summary derived
    # from terminal status + exit_code for non-passing results.
    # capability-skipped is NOT a failure - the run was intentionally skipped.
    let result_status = ($result.status | default "")
    let is_cap_skipped = ($result_status == "capability-skipped")
    let has_failure = (not $is_cap_skipped) and ((($result.exit_code | default 0) != 0) or ($result_status != "passed"))
    mut failure_reason = ($run.error? | default "")
    if (($failure_reason | is-empty) and $has_failure) {
        $failure_reason = $"status=($result_status) exit_code=($result.exit_code)"
    }
    let failure_reason_val = if ($failure_reason | is-empty) { null } else { $failure_reason }
    mut run_entry = {
        id: $run_id,
        cell_id: $cell.cell_id,
        execution_id: $run.execution_id,
        artifact_name: ($cell.artifact_name? | default ""),
        matrix_key: $matrix_key,
        attempt_number: 1,
        retry_of_run_id: null,
        superseded_by_run_id: null,
        lifecycle_status: "completed",
        started_at: ($run.started_at? | default ""),
        finished_at: ($run.finished_at? | default ""),
        stack_id: ($run.stack_id? | default ""),
    }

    # result entry: evidence rows live here
    mut result_entry = {
        id: $result_id,
        run_id: $result_run_id,
        cell_id: $cell.cell_id,
        matrix_key: $matrix_key,
        status: $result.status,
        exit_code: $result.exit_code,
        finished_at: $result.finished_at,
        evidence: $ev_rows,
    }
    if $failure_reason_val != null {
        $result_entry = ($result_entry | upsert failure_reason $failure_reason_val)
    }

    mut manifest = {
        schema_version: 1,
        generated_at: $generated_at,
        producer: {name: "ocmts", version: "0.1.0"},
        execution_context: $ctx,
        flows: {($flow_id): $flow_entry},
        cells: {($cell.cell_id): $cell_entry},
        runs: {($run_id): $run_entry},
        results: {($result_id): $result_entry},
        indexes: {
            latest_terminal_result_by_cell: {($cell.cell_id): $result_id}
        },
    }
    if not ($suite_id | is-empty) { $manifest = ($manifest | upsert suite_id $suite_id) }
    if not ($suite_kind | is-empty) { $manifest = ($manifest | upsert suite_kind $suite_kind) }
    let manifest = $manifest

    let errs = (consistency-errors $manifest)

    # Write suite-manifest.v1.json even on consistency failure, for debuggability.
    $manifest | to json --indent 2
        | save --force ($meta_dir | path join "suite-manifest.v1.json")

    # Throw after writing so the files exist for debugging.
    if not ($errs | is-empty) {
        let msg = ($errs | str join "; ")
        error make {msg: $"publish-envelope consistency errors: ($msg)"}
    }
}

# Safe wrapper: calls emit-publish-envelope and logs any error as a warning.
# Non-fatal; does not throw.
export def publish-envelope-safe [artifacts_base: string] {
    try {
        emit-publish-envelope $artifacts_base
    } catch {|e|
        print $"WARNING: publish-envelope failed for ($artifacts_base): ($e.msg)"
    }
}
