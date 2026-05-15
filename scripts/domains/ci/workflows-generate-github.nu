# Generate committed .github/workflows/ YAML files from the planner and config.
# Filenames come from config/ci/workflows.nuon (github.filenames.*); defaults in parens.
# Writes:
#   .github/workflows/<matrix>           (ci-matrix.yml)   - orchestration workflow (flow-id jobs)
#   .github/workflows/<run_wave>         (ci-run-wave.yml) - reusable per-flow matrix runner
#   .github/workflows/<run_cell>         (ci-run-cell.yml) - reusable single-cell runner
#   .github/workflows/<site>             (ci-site.yml)     - site publish (workflow_call + workflow_dispatch)
#   .github/workflows/assets/<flow>.json                   - per-flow cell data (one per active flow)
#
# Stale asset files are removed automatically. The assets directory is
# generator-owned; do not add files there manually.
#
# To regenerate after changing config/matrix/,
# config/ci/prerequisites.nuon, config/ci/toolchain.nuon, or config/site.nuon, run:
#   nu scripts/ocmts.nu ci workflows generate github

use ../../lib/ci/planner.nu [plan-suite]
use ../../lib/ci/workflow-gen.nu [
    build-ci-matrix-yml build-run-wave-yml build-run-cell-yml build-ci-site-yml build-flow-assets
]
use ../../lib/domain/core/ocmts-root.nu [get-ocmts-root]
use ../../lib/matrix/rules-gen.nu [load-matrix-rules]
use ../../lib/site/flow-caps.nu [load-flow-caps]

def main [
    --dry-run,  # Print generated YAML and JSON to stdout instead of writing files
] {
    let root = get-ocmts-root
    let wf_config = (open ($root | path join "config/ci/workflows.nuon"))
    let gh_filenames = $wf_config.github.filenames
    let matrix_filename = ($gh_filenames.matrix? | default "ci-matrix.yml")
    let run_wave_filename = ($gh_filenames.run_wave? | default "ci-run-wave.yml")
    let run_cell_filename = ($gh_filenames.run_cell? | default "ci-run-cell.yml")
    let site_filename = ($gh_filenames.site? | default "ci-site.yml")
    let rules = (load-matrix-rules $root)
    let prereqs = open ($root | path join "config/ci/prerequisites.nuon")
    let flow_caps = (load-flow-caps ($root | path join "config/matrix/flows"))
    let adapters = (open ($root | path join "config/adapters/capabilities.v1.nuon") | get adapters)
    let plan = plan-suite $rules $prereqs $flow_caps $adapters

    let matrix_yml = (build-ci-matrix-yml $plan)
    let run_wave_yml = (build-run-wave-yml)
    let run_cell_yml = (build-run-cell-yml)
    let ci_site_yml = (build-ci-site-yml)
    let flow_assets = (build-flow-assets $plan)

    if $dry_run {
        print $"# === ($matrix_filename) ==="
        print $matrix_yml
        print $"\n# === ($run_wave_filename) ==="
        print $run_wave_yml
        print $"\n# === ($run_cell_filename) ==="
        print $run_cell_yml
        print $"\n# === ($site_filename) ==="
        print $ci_site_yml
        for asset in $flow_assets {
            print $"\n# === ($asset.path) ==="
            print $asset.content
        }
        return
    }

    let wf_dir = ($root | path join ".github/workflows")
    let assets_dir = ($wf_dir | path join "assets")
    mkdir $assets_dir
    $matrix_yml | save --force ($wf_dir | path join $matrix_filename)
    $run_wave_yml | save --force ($wf_dir | path join $run_wave_filename)
    $run_cell_yml | save --force ($wf_dir | path join $run_cell_filename)
    $ci_site_yml | save --force ($wf_dir | path join $site_filename)

    # Write per-flow asset files.
    for asset in $flow_assets {
        let abs_path = ($root | path join $asset.path)
        $asset.content | save --force $abs_path
    }

    # Reconcile: remove stale asset files no longer in the generated set.
    let expected_names = ($flow_assets | each {|a| $a.path | path basename})
    let existing_names = (
        glob $"($assets_dir)/*.json" | each {|p| $p | path basename}
    )
    for name in $existing_names {
        if not ($name in $expected_names) {
            rm ($assets_dir | path join $name)
            print $"Removed stale asset: .github/workflows/assets/($name)"
        }
    }

    print "Generated workflows:"
    print $"  ($wf_dir | path join $matrix_filename)"
    print $"  ($wf_dir | path join $run_wave_filename)"
    print $"  ($wf_dir | path join $run_cell_filename)"
    print $"  ($wf_dir | path join $site_filename)"
    for asset in $flow_assets {
        print $"  ($root | path join $asset.path)"
    }
}
