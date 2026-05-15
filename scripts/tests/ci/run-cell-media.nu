# ci-run-cell.yml media, optimizer, and public-command tests.
# Run: nu scripts/tests/ci/run-cell-media.nu
# Returns exit 0 on all pass, exit 1 with details on failure.

const SUITE_PATH = path self

use ../../lib/ci/planner.nu [plan-suite]
use ../../lib/ci/workflow-gen.nu [
    build-ci-matrix-yml
    build-run-cell-yml
]
use ../../lib/tests/assert.nu *
use ../../lib/tests/runner.nu [run-suite]
use ./fixtures.nu [fixture-rules fixture-prereqs fixture-flow-caps]

# ---- tests ----

def test-run-cell-has-optimize-media-step [] {
    test-log "\n[test-run-cell-has-optimize-media-step]"
    let run_cell_yml = (build-run-cell-yml)
    let optimize_pos = ($run_cell_yml | str index-of "Optimize cell media")
    let upload_pos = ($run_cell_yml | str index-of "Upload optimized media artifact")
    let optimize_section = ($run_cell_yml | str substring $optimize_pos..$upload_pos)
    [
        (assert-truthy ($run_cell_yml | str contains "Optimize cell media")
            "ci-run-cell.yml has Optimize cell media step")
        (assert-truthy ($run_cell_yml | str contains "optimize-media")
            "ci-run-cell.yml calls optimize-media command")
        (assert-truthy ($run_cell_yml | str contains "--raw-dir .")
            "ci-run-cell.yml passes --raw-dir . (repo root) to optimize-media")
        (assert-truthy (not ($run_cell_yml | str contains "--raw-dir artifacts/"))
            "ci-run-cell.yml does not pass --raw-dir artifacts/ to optimize-media")
        (assert-truthy ($run_cell_yml | str contains "--output-dir artifacts-optimized/")
            "ci-run-cell.yml passes --output-dir artifacts-optimized/ to optimize-media")
        (assert-truthy (not ($optimize_section | str contains "continue-on-error: true"))
            "optimize-media step does not ignore optimizer failures")
    ]
}

def test-run-cell-uploads-optimized-media-artifact [] {
    test-log "\n[test-run-cell-uploads-optimized-media-artifact]"
    let run_cell_yml = (build-run-cell-yml)
    [
        (assert-truthy ($run_cell_yml | str contains "Upload optimized media artifact")
            "ci-run-cell.yml has Upload optimized media artifact step")
        (assert-truthy ($run_cell_yml | str contains "optimized-media-${{ inputs['artifact-name'] }}")
            "ci-run-cell.yml uploads artifact named optimized-media-<artifact-name> (no doubled cell-)")
        (assert-truthy (not ($run_cell_yml | str contains "cell-cell-"))
            "ci-run-cell.yml artifact name does not contain doubled cell-cell- prefix")
        (assert-truthy ($run_cell_yml | str contains "path: artifacts-optimized/")
            "ci-run-cell.yml uploads artifacts-optimized/ directory")
        (assert-truthy ($run_cell_yml | str contains "if-no-files-found: error")
            "optimized upload requires optimized artifact files")
    ]
}

def test-run-cell-has-prepull-optimizer-step [] {
    test-log "\n[test-run-cell-has-prepull-optimizer-step]"
    let run_cell_yml = (build-run-cell-yml)
    let prepull_pos = ($run_cell_yml | str index-of "Pre-pull optimizer image")
    let optimize_pos = ($run_cell_yml | str index-of "Optimize cell media")
    let prepull_section = ($run_cell_yml | str substring $prepull_pos..$optimize_pos)
    [
        (assert-truthy ($run_cell_yml | str contains "Pre-pull optimizer image")
            "ci-run-cell.yml has Pre-pull optimizer image step")
        (assert-truthy ($prepull_section | str contains "docker pull")
            "Pre-pull optimizer image step runs docker pull")
        (assert-truthy ($prepull_section | str contains "always()")
            "Pre-pull optimizer image step has always() semantics")
        (assert-truthy ($prepull_section | str contains "refs/heads/main")
            "Pre-pull optimizer image step is gated on publish branch")
        (assert-truthy ($prepull_pos < $optimize_pos)
            "Pre-pull optimizer image step appears before Optimize cell media")
    ]
}

def test-public-commands-in-generated-yaml [] {
    test-log "\n[test-public-commands-in-generated-yaml]"
    let rules = fixture-rules
    let prereqs = fixture-prereqs
    let plan = (plan-suite $rules $prereqs (fixture-flow-caps) {})
    let matrix_yml = (build-ci-matrix-yml $plan)
    let run_cell_yml = (build-run-cell-yml)
    [
        (assert-truthy ($matrix_yml | str contains "nu scripts/ocmts.nu ci suite-id")
            "ci-matrix.yml uses public nu scripts/ocmts.nu ci suite-id command")
        (assert-truthy ($run_cell_yml | str contains "nu scripts/ocmts.nu ci exec-id")
            "ci-run-cell.yml uses public nu scripts/ocmts.nu ci exec-id command")
        (assert-truthy ($run_cell_yml | str contains "nu scripts/ocmts.nu ci check-prereq-status")
            "ci-run-cell.yml uses public nu scripts/ocmts.nu ci check-prereq-status command")
        (assert-truthy ($run_cell_yml | str contains "nu scripts/ocmts.nu ci download-prereqs")
            "ci-run-cell.yml uses public nu scripts/ocmts.nu ci download-prereqs command")
        (assert-truthy ($run_cell_yml | str contains "nu scripts/ocmts.nu artifacts show-optimizer-image")
            "ci-run-cell.yml uses public nu scripts/ocmts.nu artifacts show-optimizer-image command")
        (assert-truthy ($run_cell_yml | str contains "nu scripts/ocmts.nu services list-cell-images")
            "ci-run-cell.yml uses public nu scripts/ocmts.nu services list-cell-images for pre-pull")
        (assert-truthy (not ($run_cell_yml | str contains "nu -c \"use scripts/lib/images"))
            "ci-run-cell.yml does not use internal nu -c image import in pre-pull step")
    ]
}

def test-run-cell-prepull-runtime-images-gated [] {
    test-log "\n[test-run-cell-prepull-runtime-images-gated]"
    let run_cell_yml = (build-run-cell-yml)
    let prepull_pos = ($run_cell_yml | str index-of "Pre-pull runtime images")
    let run_pos = ($run_cell_yml | str index-of "Run cell (when no prerequisite failure)")
    let prepull_section = ($run_cell_yml | str substring $prepull_pos..$run_pos)
    [
        (assert-truthy ($prepull_section | str contains "inputs['failure-reason'] == ''")
            "Pre-pull runtime images is gated: no failure-reason")
        (assert-truthy ($prepull_section | str contains "steps.prereq_check.outputs['prereq-failure-reason'] == ''")
            "Pre-pull runtime images is gated: no prereq failure")
        (assert-truthy ($prepull_section | str contains "docker pull")
            "Pre-pull runtime images step runs docker pull")
        (assert-truthy ($prepull_pos < $run_pos)
            "Pre-pull runtime images step appears before Run cell step")
    ]
}

def test-run-cell-optimize-branch-gated [] {
    test-log "\n[test-run-cell-optimize-branch-gated]"
    let run_cell_yml = (build-run-cell-yml)
    # Both optimize and upload steps must be gated on publish_branch_gate.
    let optimize_pos = ($run_cell_yml | str index-of "Optimize cell media")
    let upload_opt_pos = ($run_cell_yml | str index-of "Upload optimized media artifact")
    let optimize_section = ($run_cell_yml | str substring $optimize_pos..$upload_opt_pos)
    let upload_opt_section = ($run_cell_yml | str substring $upload_opt_pos..)
    [
        (assert-truthy ($optimize_section | str contains "always()")
            "optimize-media step has always() semantics")
        (assert-truthy ($optimize_section | str contains "refs/heads/main")
            "optimize-media step is gated on publish branch gate")
        (assert-truthy ($upload_opt_section | str contains "refs/heads/main")
            "upload optimized media step is gated on publish branch gate")
        (assert-truthy ($upload_opt_section | str contains "always()")
            "upload optimized media step has always() semantics")
    ]
}

def main [] {
    test-log "=== CI run-cell media tests ==="
    let results = (
        (test-run-cell-has-optimize-media-step)
        | append (test-run-cell-uploads-optimized-media-artifact)
        | append (test-run-cell-has-prepull-optimizer-step)
        | append (test-public-commands-in-generated-yaml)
        | append (test-run-cell-optimize-branch-gated)
        | append (test-run-cell-prepull-runtime-images-gated)
    ) | flatten
    run-suite "ci/run-cell-media" $SUITE_PATH $results
}
