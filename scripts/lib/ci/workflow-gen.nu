# CI workflow YAML generators using blueprint templates.
# Builds ci-matrix.yml, ci-run-wave.yml, and ci-run-cell.yml from a plan record.
# Also produces per-flow JSON asset files under .github/workflows/assets/.
# Exported so ci/mod.nu and tests can import directly.
#
# Key properties:
# - suite_id is NOT baked at generation time; the `setup` job generates a
#   fresh one at workflow runtime and shares it via job outputs.
# - execution_id is NOT baked per-cell; ci-run-cell.yml generates a fresh
#   one per cell at runtime in a dedicated step.
# - artifact-name (e.g. cell-login-nextcloud-v34) is stable and derived from
#   scenario+participants, so embedding it in YAML is safe and necessary.
# - cells-json is no longer inline in ci-matrix.yml; each flow's cells are
#   stored in .github/workflows/assets/<flow>.json and loaded at runtime by
#   a load-cells job in ci-run-wave.yml.

use ./template-renderer.nu [render-blueprint render-template]
use ./flow-order.nu [sort-cells-by-flow-order]
use ../domain/core/ocmts-root.nu [get-ocmts-root]

# Build the aggregate needs block (multi-line YAML fragment).
# Returns the indented `needs:` block string.
export def build-aggregate-needs-block [job_names: list<string>]: any -> string {
    let all_needs = (["setup"] | append $job_names)
    let items = ($all_needs | each {|n| $"        ($n),"} | str join "\n")
    $"    needs:\n      [\n($items)\n      ]"
}

# Format the display_name string for one-party or two-party cells.
# Used as the cell-layer job title; the wave layer uses a fixed "test" label,
# so this returns only the pair part to avoid duplicated prefixes in the UI.
# Format: <sender_platform> <sender_version> [to <recv_platform> <recv_version>]
def cell-display-name [
    sender_platform: string,
    sender_version: string,
    is_two_party: bool,
    recv_platform: string,
    recv_version: string,
]: any -> string {
    if $is_two_party {
        $"($sender_platform) ($sender_version) to ($recv_platform) ($recv_version)"
    } else {
        $"($sender_platform) ($sender_version)"
    }
}

# Build a cell record for asset JSON (all fields needed by ci-run-cell.yml).
def build-cell-json-record [
    cell: record,
    cell_id_to_artifact: record,
]: any -> record {
    let recv_platform = if $cell.is_two_party { $cell.receiver_platform } else { "" }
    let recv_version = if $cell.is_two_party { $cell.receiver_version } else { "" }
    let deps = ($cell.depends_on? | default [])
    let cell_depends_on = if ($deps | is-empty) {
        ""
    } else {
        $deps | each {|dep_id|
            $cell_id_to_artifact | get --optional $dep_id | default ""
        } | where {|a| not ($a | is-empty)} | str join ","
    }
    let display_name = (cell-display-name
        $cell.sender_platform $cell.sender_version
        $cell.is_two_party $recv_platform $recv_version)
    {
        scenario: $cell.scenario
        sender_platform: $cell.sender_platform
        sender_version: $cell.sender_version
        receiver_platform: $recv_platform
        receiver_version: $recv_version
        display_name: $display_name
        artifact_name: $cell.artifact_name
        cell_id: $cell.cell_id
        cell_depends_on: $cell_depends_on
    }
}

# Relative path for a flow's cell JSON asset file.
def flow-asset-rel-path [flow_id: string]: any -> string {
    $".github/workflows/assets/($flow_id).json"
}

# Build pretty-printed JSON content for a flow asset file.
export def build-flow-asset-content [cells: list]: any -> string {
    ($cells | to json --indent 2) + "\n"
}

# Build all per-flow asset files for the generated workflow set.
# Returns list of {path: string, content: string} where path is
# relative (e.g. .github/workflows/assets/login.json).
export def build-flow-assets [plan: record]: any -> list {
    let root = get-ocmts-root
    let cfg = (load-ci-config $root)
    let gh = $cfg.workflows.github

    let runnable_cells = ($plan.cells | where capability_action == "run")
    let ordered_cells = (sort-cells-by-flow-order $runnable_cells $gh.job_order)
    let cell_id_to_artifact = ($runnable_cells | reduce --fold {} {|c, acc|
        $acc | upsert $c.cell_id $c.artifact_name
    })
    let flow_ids_ordered = ($ordered_cells | each {|c| $c.flow_id} | uniq)
    let cells_by_flow = ($ordered_cells | group-by flow_id)

    $flow_ids_ordered | each {|flow_id|
        let flow_cells = ($cells_by_flow | get --optional $flow_id | default [])
        if ($flow_cells | is-empty) { return null }
        let cell_records = ($flow_cells | enumerate | each {|e|
            (build-cell-json-record $e.item $cell_id_to_artifact)
            | insert wave_index ($e.index + 1)
        })
        {
            path: (flow-asset-rel-path $flow_id)
            content: (build-flow-asset-content $cell_records)
        }
    } | where {|a| $a != null}
}

# Render a single flow job YAML fragment for ci-matrix.yml.
# Each flow job calls ci-run-wave.yml with cells-path pointing to the
# pre-generated asset file for that flow.
def render-flow-job [
    flow_id: string,
    needs: list<string>,
    cells_path: string,
    run_wave_filename: string,
]: any -> string {
    let needs_str = ($needs | str join ", ")
    [
        $"  ($flow_id):"
        $"    needs: [($needs_str)]"
        "    if: always() && needs.setup.result == 'success'"
        $"    uses: ./.github/workflows/($run_wave_filename)"
        "    with:"
        $"      flow-id: ($flow_id)"
        "      suite-id: ${{ needs.setup.outputs['suite-id'] }}"
        $"      cells-path: ($cells_path)"
    ] | str join "\n"
}

# Load CI config records from the repo.
def load-ci-config [root: string]: any -> record {
    let toolchain = (open ($root | path join "config/ci/toolchain.nuon"))
    let workflows = (open ($root | path join "config/ci/workflows.nuon"))
    {toolchain: $toolchain, workflows: $workflows}
}

# Load site config from config/site.nuon.
def load-site-config [root: string]: any -> record {
    open ($root | path join "config/site.nuon")
}

# Blueprint path helpers.
def bp-path [root: string, rel: string]: any -> string {
    $root | path join "scripts/lib/ci/blueprints" $rel
}

# Generate ci-matrix.yml YAML content using per-flow job strategy.
# Each enabled flow in config job_order becomes a separate GitHub Actions job.
# Cells are grouped by flow_id; each flow job passes cells-path to
# ci-run-wave.yml pointing at the pre-generated asset JSON for that flow.
# suite_id and per-cell execution_ids are resolved at workflow runtime, not
# embedded here. The `plan` argument provides cell topology (deps, scenario,
# participants, artifact_name) which are all stable across runs.
export def build-ci-matrix-yml [plan: record] {
    let root = get-ocmts-root
    let cfg = (load-ci-config $root)
    let site_cfg = (load-site-config $root)
    let gh = $cfg.workflows.github
    let nu_ver = $cfg.toolchain.nushell.version
    let run_wave_filename = ($gh.filenames.run_wave? | default "ci-run-wave.yml")
    let site_filename = ($gh.filenames.site? | default "ci-site.yml")
    let publish_branch_gate = ($site_cfg.publish_branch_gate? | default "main")
    let raw_agg_name = ($site_cfg.raw_aggregate_artifact_name? | default "aggregate-summary")

    let ordered_cells = (sort-cells-by-flow-order ($plan.cells | where capability_action == "run") $gh.job_order)
    let flow_ids_ordered = ($ordered_cells | each {|c| $c.flow_id} | uniq)
    let cells_by_flow = ($ordered_cells | group-by flow_id)

    # Emit one job per flow that has cells, in visual order.
    # Each subsequent flow job needs all prior emitted flow jobs.
    mut emitted_flows: list<string> = []
    mut flow_job_fragments: list<string> = []

    for flow_id in $flow_ids_ordered {
        let flow_cells = ($cells_by_flow | get --optional $flow_id | default [])
        if ($flow_cells | is-empty) { continue }
        let cells_path = (flow-asset-rel-path $flow_id)
        let needs = (["setup"] | append $emitted_flows)
        let fragment = (render-flow-job $flow_id $needs $cells_path $run_wave_filename)
        $flow_job_fragments = ($flow_job_fragments | append ($fragment | str trim --right))
        $emitted_flows = ($emitted_flows | append $flow_id)
    }

    let flow_jobs_text = ($flow_job_fragments | str join "\n\n")
    let aggregate_needs_block = (build-aggregate-needs-block $emitted_flows)
    let matrix_tpl = (bp-path $root "github/workflows/ci-matrix.yml.tpl")

    render-blueprint $matrix_tpl {
        "generator.command": "nu scripts/ocmts.nu ci workflows generate github"
        "runner.label": $gh.runner
        "setup.nu.action": $gh.setup_nu_action
        "action.checkout": ($gh.action_checkout? | default "actions/checkout@v6")
        "action.upload.artifact": ($gh.action_upload_artifact? | default "actions/upload-artifact@v7")
        "action.download.artifact": ($gh.action_download_artifact? | default "actions/download-artifact@v7")
        "action.setup.bun": ($gh.action_setup_bun? | default "oven-sh/setup-bun@v2")
        "nushell.version": $nu_ver
        "flow.jobs": $"\n\n($flow_jobs_text)"
        "aggregate.needs.block": $aggregate_needs_block
        "publish.branch.gate": $publish_branch_gate
        "raw.aggregate.artifact.name": $raw_agg_name
        "site.workflow.filename": $site_filename
    }
}

# Generate ci-run-wave.yml YAML content.
# This reusable workflow accepts cells-path and fans out as a matrix,
# calling ci-run-cell.yml for each cell. A load-cells job reads the
# asset file and emits cells-json so run-wave can expand the matrix.
export def build-run-wave-yml [] {
    let root = get-ocmts-root
    let cfg = (load-ci-config $root)
    let gh = $cfg.workflows.github
    let nu_ver = $cfg.toolchain.nushell.version
    let max_parallel = ($gh.max_parallel? | default 0)
    let max_parallel_line = if $max_parallel > 0 {
        $"\n      max-parallel: ($max_parallel)"
    } else {
        ""
    }
    let run_cell_filename = ($gh.filenames.run_cell? | default "ci-run-cell.yml")
    let run_wave_tpl = (bp-path $root "github/workflows/ci-run-wave.yml.tpl")
    render-blueprint $run_wave_tpl {
        "generator.command": "nu scripts/ocmts.nu ci workflows generate github"
        "runner.label": $gh.runner
        "setup.nu.action": $gh.setup_nu_action
        "action.checkout": ($gh.action_checkout? | default "actions/checkout@v6")
        "nushell.version": $nu_ver
        "max_parallel_line": $max_parallel_line
        "run.cell.filename": $run_cell_filename
    }
}

# Generate ci-run-cell.yml YAML content.
# execution_id is generated per-cell at runtime in the workflow (not an input).
# artifact-name is passed from the matrix workflow as a stable derived value
# matching the 'cell-*' download pattern in the aggregate job.
# --site-cfg-overrides: optional record merged into the loaded site config;
# mirrors build-ci-site-yml for test injection without editing config.
export def build-run-cell-yml [
    --site-cfg-overrides: any = null
] {
    let root = get-ocmts-root
    let cfg = (load-ci-config $root)
    let raw_site_cfg = (load-site-config $root)
    let site_cfg = if ($site_cfg_overrides != null) {
        $raw_site_cfg | merge $site_cfg_overrides
    } else {
        $raw_site_cfg
    }
    let gh = $cfg.workflows.github
    let nu_ver = $cfg.toolchain.nushell.version
    let publish_branch_gate = ($site_cfg.publish_branch_gate? | default "main")
    let lane = ($site_cfg.media_lane_mode? | default "optimized")
    if $lane not-in ["raw" "optimized"] {
        error make {msg: $"media_lane_mode must be 'raw' or 'optimized', got: ($lane)"}
    }
    let optimized_literal = if $lane == "optimized" { "true" } else { "false" }
    let run_cell_tpl = (bp-path $root "github/workflows/ci-run-cell.yml.tpl")

    render-blueprint $run_cell_tpl {
        "generator.command": "nu scripts/ocmts.nu ci workflows generate github"
        "runner.label": $gh.runner
        "setup.nu.action": $gh.setup_nu_action
        "action.checkout": ($gh.action_checkout? | default "actions/checkout@v6")
        "action.upload.artifact": ($gh.action_upload_artifact? | default "actions/upload-artifact@v7")
        "nushell.version": $nu_ver
        "publish.branch.gate": $publish_branch_gate
        "media.lane.optimized.literal": $optimized_literal
    }
}

# Generate ci-site.yml YAML content.
# Supports workflow_call (called from ci-matrix after aggregate) and
# workflow_dispatch (manual rebuild: resolves latest successful source run).
# --site-cfg-overrides: optional record merged into the loaded site config;
# useful in tests to inject custom or empty field values without editing config.
export def build-ci-site-yml [
    --site-cfg-overrides: any = null
] {
    let root = get-ocmts-root
    let cfg = (load-ci-config $root)
    let raw_site_cfg = (load-site-config $root)
    let site_cfg = if ($site_cfg_overrides != null) {
        $raw_site_cfg | merge $site_cfg_overrides
    } else {
        $raw_site_cfg
    }
    let gh = $cfg.workflows.github
    let nu_ver = $cfg.toolchain.nushell.version
    let publish_branch_gate = ($site_cfg.publish_branch_gate? | default "main")
    let raw_agg_name = ($site_cfg.raw_aggregate_artifact_name? | default "aggregate-summary")
    let opt_pattern = ($site_cfg.optimized_artifact_pattern? | default "optimized-media-cell-*")
    let opt_agg_name = ($site_cfg.optimized_aggregate_artifact_name? | default "optimized-media-summary")
    let rebuild_src = ($site_cfg.rebuild_source_workflow? | default ($gh.filenames.matrix? | default "ci-matrix.yml"))
    # CI-owned site checkout dir (relative to the GitHub Actions working dir = repo root).
    # The site publish step clones here when no --site-dir is passed.
    let ci_site_checkout_dir = "../ocm-web-site"
    let site_output_subpath = ($site_cfg.site_build_output_path? | default "dist")
    let build_out = ($ci_site_checkout_dir | path join $site_output_subpath)
    # Deploy-target: base path and optional full URL for the Pages host repo
    # (cs3org/ocm-test-suite). Injected as ASTRO_BASE / ASTRO_SITE env vars so
    # the Astro build produces correct asset paths and canonical URLs.
    let deploy_base = ($site_cfg.deploy_base_path? | default "/")
    let deploy_site_url = ($site_cfg.deploy_site_url? | default "")
    let lane = ($site_cfg.media_lane_mode? | default "optimized")
    if $lane not-in ["raw" "optimized"] {
        error make {msg: $"media_lane_mode must be 'raw' or 'optimized', got: ($lane)"}
    }
    let optimized_literal = if $lane == "optimized" { "true" } else { "false" }
    let optimized_media_dir_scalar = if $lane == "optimized" {
        "'artifacts/optimized-summary/'"
    } else {
        "''"
    }
    let ci_site_tpl = (bp-path $root "github/workflows/ci-site.yml.tpl")

    render-blueprint $ci_site_tpl {
        "generator.command": "nu scripts/ocmts.nu ci workflows generate github"
        "runner.label": $gh.runner
        "setup.nu.action": $gh.setup_nu_action
        "action.checkout": ($gh.action_checkout? | default "actions/checkout@v6")
        "action.upload.artifact": ($gh.action_upload_artifact? | default "actions/upload-artifact@v7")
        "action.download.artifact": ($gh.action_download_artifact? | default "actions/download-artifact@v7")
        "action.setup.bun": ($gh.action_setup_bun? | default "oven-sh/setup-bun@v2")
        "action.setup.node": ($gh.action_setup_node? | default "actions/setup-node@v4")
        "node.version": ($cfg.toolchain.node?.version? | default "22.12.0")
        "action.upload.pages.artifact": ($gh.action_upload_pages_artifact? | default "actions/upload-pages-artifact@v5")
        "action.deploy.pages": ($gh.action_deploy_pages? | default "actions/deploy-pages@v5")
        "nushell.version": $nu_ver
        "publish.branch.gate": $publish_branch_gate
        "raw.aggregate.artifact.name": $raw_agg_name
        "optimized.artifact.pattern": $opt_pattern
        "optimized.aggregate.artifact.name": $opt_agg_name
        "site.rebuild.source.workflow": $rebuild_src
        "site.build.output.path": $build_out
        "astro.base": $deploy_base
        "astro.site": $deploy_site_url
        "media.lane.optimized.literal": $optimized_literal
        "media.lane.optimized.media.dir.scalar": $optimized_media_dir_scalar
    }
}
