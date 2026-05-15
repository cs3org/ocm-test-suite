# Compare committed .github/workflows/ YAML and asset JSON against freshly
# generated content. Exits nonzero and prints a useful message when drift is
# detected. Also reports stale asset files in the generator-owned assets dir.

use ../../lib/ci/planner.nu [plan-suite]
use ../../lib/ci/workflow-gen.nu [
    build-ci-matrix-yml build-run-wave-yml build-run-cell-yml build-ci-site-yml build-flow-assets
]
use ../../lib/domain/core/ocmts-root.nu [get-ocmts-root]
use ../../lib/matrix/rules-gen.nu [load-matrix-rules]
use ../../lib/site/flow-caps.nu [load-flow-caps]

def main [] {
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

    let expected_matrix = (build-ci-matrix-yml $plan)
    let expected_run_wave = (build-run-wave-yml)
    let expected_run_cell = (build-run-cell-yml)
    let expected_ci_site = (build-ci-site-yml)
    let flow_assets = (build-flow-assets $plan)

    let wf_dir = ($root | path join ".github/workflows")
    let assets_dir = ($wf_dir | path join "assets")
    let matrix_path = ($wf_dir | path join $matrix_filename)
    let run_wave_path = ($wf_dir | path join $run_wave_filename)
    let run_cell_path = ($wf_dir | path join $run_cell_filename)
    let ci_site_path = ($wf_dir | path join $site_filename)

    mut drift = false

    if not ($matrix_path | path exists) {
        print $"DRIFT: ($matrix_path) does not exist -- run: nu scripts/ocmts.nu ci workflows generate github"
        $drift = true
    } else {
        let committed_matrix = (open --raw $matrix_path)
        if $committed_matrix != $expected_matrix {
            print $"DRIFT: ($matrix_path) is out of date -- run: nu scripts/ocmts.nu ci workflows generate github"
            $drift = true
        } else {
            print $"ok: ($matrix_path)"
        }
    }

    if not ($run_wave_path | path exists) {
        print $"DRIFT: ($run_wave_path) does not exist -- run: nu scripts/ocmts.nu ci workflows generate github"
        $drift = true
    } else {
        let committed_run_wave = (open --raw $run_wave_path)
        if $committed_run_wave != $expected_run_wave {
            print $"DRIFT: ($run_wave_path) is out of date -- run: nu scripts/ocmts.nu ci workflows generate github"
            $drift = true
        } else {
            print $"ok: ($run_wave_path)"
        }
    }

    if not ($run_cell_path | path exists) {
        print $"DRIFT: ($run_cell_path) does not exist -- run: nu scripts/ocmts.nu ci workflows generate github"
        $drift = true
    } else {
        let committed_run_cell = (open --raw $run_cell_path)
        if $committed_run_cell != $expected_run_cell {
            print $"DRIFT: ($run_cell_path) is out of date -- run: nu scripts/ocmts.nu ci workflows generate github"
            $drift = true
        } else {
            print $"ok: ($run_cell_path)"
        }
    }

    if not ($ci_site_path | path exists) {
        print $"DRIFT: ($ci_site_path) does not exist -- run: nu scripts/ocmts.nu ci workflows generate github"
        $drift = true
    } else {
        let committed_ci_site = (open --raw $ci_site_path)
        if $committed_ci_site != $expected_ci_site {
            print $"DRIFT: ($ci_site_path) is out of date -- run: nu scripts/ocmts.nu ci workflows generate github"
            $drift = true
        } else {
            print $"ok: ($ci_site_path)"
        }
    }

    # Check per-flow asset files.
    let expected_asset_names = ($flow_assets | each {|a| $a.path | path basename})
    for asset in $flow_assets {
        let abs_path = ($root | path join $asset.path)
        if not ($abs_path | path exists) {
            print $"DRIFT: ($asset.path) does not exist -- run: nu scripts/ocmts.nu ci workflows generate github"
            $drift = true
        } else {
            let committed = (open --raw $abs_path)
            if $committed != $asset.content {
                print $"DRIFT: ($asset.path) is out of date -- run: nu scripts/ocmts.nu ci workflows generate github"
                $drift = true
            } else {
                print $"ok: ($asset.path)"
            }
        }
    }

    # Detect stale asset files that are no longer generated.
    if ($assets_dir | path exists) {
        let existing_names = (
            glob $"($assets_dir)/*.json" | each {|p| $p | path basename}
        )
        for name in $existing_names {
            if not ($name in $expected_asset_names) {
                print $"STALE: .github/workflows/assets/($name) is no longer generated -- run: nu scripts/ocmts.nu ci workflows generate github"
                $drift = true
            }
        }
    }

    if $drift {
        error make {msg: "Workflow drift detected. Regenerate with: nu scripts/ocmts.nu ci workflows generate github"}
    }
}
