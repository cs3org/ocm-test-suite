# Generate committed .github/workflows/ YAML files from the planner and config.
# Writes:
#   .github/workflows/ci-matrix.yml                - orchestration workflow (flow-id jobs)
#   .github/workflows/ci-run-wave.yml              - reusable per-flow matrix runner
#   .github/workflows/ci-run-cell.yml              - reusable single-cell runner
#   .github/workflows/ci-site.yml                  - site publish (workflow_call + workflow_dispatch)
#   .github/workflows/assets/<flow>.json           - per-flow cell data (one per active flow)
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

def main [
    --dry-run,  # Print generated YAML and JSON to stdout instead of writing files
] {
    let root = get-ocmts-root
    let rules = (load-matrix-rules $root)
    let prereqs = open ($root | path join "config/ci/prerequisites.nuon")
    let plan = plan-suite $rules $prereqs

    let matrix_yml = (build-ci-matrix-yml $plan)
    let run_wave_yml = (build-run-wave-yml)
    let run_cell_yml = (build-run-cell-yml)
    let ci_site_yml = (build-ci-site-yml)
    let flow_assets = (build-flow-assets $plan)

    if $dry_run {
        print "# === ci-matrix.yml ==="
        print $matrix_yml
        print "\n# === ci-run-wave.yml ==="
        print $run_wave_yml
        print "\n# === ci-run-cell.yml ==="
        print $run_cell_yml
        print "\n# === ci-site.yml ==="
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
    $matrix_yml | save --force ($wf_dir | path join "ci-matrix.yml")
    $run_wave_yml | save --force ($wf_dir | path join "ci-run-wave.yml")
    $run_cell_yml | save --force ($wf_dir | path join "ci-run-cell.yml")
    $ci_site_yml | save --force ($wf_dir | path join "ci-site.yml")

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
    print $"  ($wf_dir | path join 'ci-matrix.yml')"
    print $"  ($wf_dir | path join 'ci-run-wave.yml')"
    print $"  ($wf_dir | path join 'ci-run-cell.yml')"
    print $"  ($wf_dir | path join 'ci-site.yml')"
    for asset in $flow_assets {
        print $"  ($root | path join $asset.path)"
    }
}
