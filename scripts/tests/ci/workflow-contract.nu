# Run-wave/run-cell/matrix contract, wiring, and expression tests.
# Covers: caller/callee relationships, cell-depends-on wiring,
# bracket-notation expression hardening, and load-cells pattern.
# Run: nu scripts/tests/ci/workflow-contract.nu
# Returns exit 0 on all pass, exit 1 with details on failure.

const SUITE_PATH = path self

use ../../lib/ci/planner.nu [plan-suite]
use ../../lib/ci/workflow-gen.nu [
    build-ci-matrix-yml
    build-run-wave-yml
    build-run-cell-yml
]
use ../../lib/tests/assert.nu *
use ../../lib/tests/runner.nu [run-suite]
use ../../lib/tests/fixtures.nu [with-tmp-dir]
use ./fixtures.nu [fixture-rules fixture-prereqs fixture-flow-caps]

# ---- tests ----

def test-blocked-output-check [] {
    test-log "\n[test-blocked-output-check]"
    let run_wave_yml = (build-run-wave-yml)
    # Per-cell prereq checking runs at runtime inside ci-run-cell.yml.
    # ci-run-wave.yml passes cell_depends_on so ci-run-cell.yml can download
    # and inspect the prerequisite artifact.
    [
        (assert-truthy ($run_wave_yml | str contains "cell-depends-on:")
            "ci-run-wave.yml passes cell-depends-on to ci-run-cell.yml")
    ]
}

def test-matrix-calls-run-wave [] {
    test-log "\n[test-matrix-calls-run-wave]"
    let real_root = ($SUITE_PATH | path dirname | path dirname | path dirname | path dirname)
    let wf = (open ($real_root | path join "config/ci/workflows.nuon"))
    let run_wave = ($wf.github.filenames.run_wave? | default "ci-run-wave.yml")
    let rules = fixture-rules
    let prereqs = fixture-prereqs
    let plan = (plan-suite $rules $prereqs (fixture-flow-caps) {})
    let yml = (build-ci-matrix-yml $plan)
    [
        (assert-truthy ($yml | str contains $"./.github/workflows/($run_wave)")
            "ci-matrix.yml calls configured run-wave workflow path")
    ]
}

def test-run-wave-calls-run-cell [] {
    test-log "\n[test-run-wave-calls-run-cell]"
    let real_root = ($SUITE_PATH | path dirname | path dirname | path dirname | path dirname)
    let wf = (open ($real_root | path join "config/ci/workflows.nuon"))
    let run_cell = ($wf.github.filenames.run_cell? | default "ci-run-cell.yml")
    let run_wave_yml = (build-run-wave-yml)
    [
        (assert-truthy ($run_wave_yml | str contains $"./.github/workflows/($run_cell)")
            "ci-run-wave.yml calls configured run-cell workflow path")
    ]
}

def test-run-wave-properties [] {
    test-log "\n[test-run-wave-properties]"
    let run_wave_yml = (build-run-wave-yml)
    [
        (assert-truthy ($run_wave_yml | str contains "fromJson(needs['load-cells'].outputs['cells-json'])")
            "ci-run-wave.yml uses fromJson with bracket notation for hyphenated names")
        (assert-truthy ($run_wave_yml | str contains "fail-fast: false")
            "ci-run-wave.yml sets fail-fast: false")
        (assert-truthy ($run_wave_yml | str contains "cell_depends_on")
            "ci-run-wave.yml passes cell_depends_on to ci-run-cell.yml")
    ]
}

def test-cells-path-in-matrix [] {
    test-log "\n[test-cells-path-in-matrix]"
    let rules = fixture-rules
    let prereqs = fixture-prereqs
    let plan = (plan-suite $rules $prereqs (fixture-flow-caps) {})
    let yml = (build-ci-matrix-yml $plan)
    [
        (assert-truthy ($yml | str contains "cells-path:")
            "ci-matrix.yml flow jobs use cells-path:")
        (assert-truthy (not ($yml | str contains "cells-json: '["))
            "ci-matrix.yml flow jobs do not contain inline cells-json values")
        (assert-truthy ($yml | str contains ".github/workflows/assets/")
            "ci-matrix.yml flow jobs reference assets directory")
    ]
}

def test-load-cells-job-in-run-wave [] {
    test-log "\n[test-load-cells-job-in-run-wave]"
    let run_wave_yml = (build-run-wave-yml)
    [
        (assert-truthy ($run_wave_yml | str contains "load-cells:")
            "ci-run-wave.yml has a load-cells job")
        (assert-truthy ($run_wave_yml | str contains "cells-path:")
            "ci-run-wave.yml accepts cells-path input")
        (assert-truthy ($run_wave_yml | str contains "needs: [load-cells]")
            "ci-run-wave.yml run-wave job depends on load-cells")
        (assert-truthy ($run_wave_yml | str contains "nu scripts/ocmts.nu ci read-cells-json")
            "ci-run-wave.yml load-cells job reads JSON via repo-owned read-cells-json command")
    ]
}

def test-run-wave-nushell-load-cells [] {
    test-log "\n[test-run-wave-nushell-load-cells]"
    let real_root = ($SUITE_PATH | path dirname | path dirname | path dirname | path dirname)
    let toolchain = (open ($real_root | path join "config/ci/toolchain.nuon"))
    let nu_ver = $toolchain.nushell.version
    let run_wave_yml = (build-run-wave-yml)
    [
        (assert-truthy ($run_wave_yml | str contains "nu scripts/ocmts.nu ci read-cells-json")
            "ci-run-wave.yml uses repo-owned read-cells-json for cell loading")
        (assert-truthy (not ($run_wave_yml | str contains "jq"))
            "ci-run-wave.yml does not call jq")
        (assert-truthy ($run_wave_yml | str contains $"version: '($nu_ver)'")
            "ci-run-wave.yml installs nushell with pinned version in load-cells job")
    ]
}

def test-hardened-cell-expressions [] {
    test-log "\n[test-hardened-cell-expressions]"
    let run_cell_yml = (build-run-cell-yml)
    [
        (assert-truthy ($run_cell_yml | str contains "inputs['failure-reason']")
            "ci-run-cell.yml uses bracket notation for inputs.failure-reason")
        (assert-truthy ($run_cell_yml | str contains "inputs['cell-depends-on']")
            "ci-run-cell.yml uses bracket notation for inputs.cell-depends-on")
        (assert-truthy ($run_cell_yml | str contains "steps.cell.outputs['execution-id']")
            "ci-run-cell.yml uses bracket notation for steps.cell.outputs.execution-id")
        (assert-truthy ($run_cell_yml | str contains "steps.prereq_check.outputs['prereq-failure-reason']")
            "ci-run-cell.yml uses bracket notation for prereq-failure-reason output")
        (assert-truthy ($run_cell_yml | str contains "inputs['suite-id']")
            "ci-run-cell.yml uses bracket notation for inputs.suite-id")
        (assert-truthy ($run_cell_yml | str contains "inputs['artifact-name']")
            "ci-run-cell.yml uses bracket notation for inputs.artifact-name")
        (assert-truthy ($run_cell_yml | str contains "jobs['run-cell'].outputs['cell-status']")
            "ci-run-cell.yml uses bracket notation for jobs.run-cell output")
        (assert-truthy (not ($run_cell_yml | str contains "inputs.failure-reason"))
            "ci-run-cell.yml has no dot-notation inputs.failure-reason")
        (assert-truthy (not ($run_cell_yml | str contains "inputs.cell-depends-on"))
            "ci-run-cell.yml has no dot-notation inputs.cell-depends-on")
    ]
}

def test-hardened-wave-expressions [] {
    test-log "\n[test-hardened-wave-expressions]"
    let run_wave_yml = (build-run-wave-yml)
    [
        (assert-truthy ($run_wave_yml | str contains "inputs['cells-path']")
            "ci-run-wave.yml uses bracket notation for inputs.cells-path")
        (assert-truthy ($run_wave_yml | str contains "inputs['suite-id']")
            "ci-run-wave.yml uses bracket notation for inputs.suite-id")
        (assert-truthy ($run_wave_yml | str contains "needs['load-cells'].outputs['cells-json']")
            "ci-run-wave.yml uses bracket notation for needs.load-cells.outputs.cells-json")
        (assert-truthy ($run_wave_yml | str contains "steps.read.outputs['cells-json']")
            "ci-run-wave.yml uses bracket notation for load-cells step output")
        (assert-truthy (not ($run_wave_yml | str contains "inputs.cells-path"))
            "ci-run-wave.yml has no dot-notation inputs.cells-path")
        (assert-truthy (not ($run_wave_yml | str contains "inputs.suite-id"))
            "ci-run-wave.yml has no dot-notation inputs.suite-id")
    ]
}

def test-hardened-matrix-expressions [] {
    test-log "\n[test-hardened-matrix-expressions]"
    let rules = fixture-rules
    let prereqs = fixture-prereqs
    let plan = (plan-suite $rules $prereqs (fixture-flow-caps) {})
    let yml = (build-ci-matrix-yml $plan)
    [
        (assert-truthy ($yml | str contains "needs.setup.outputs['suite-id']")
            "ci-matrix.yml uses bracket notation for needs.setup.outputs.suite-id")
        (assert-truthy ($yml | str contains "inputs['suite-id']")
            "ci-matrix.yml uses bracket notation for inputs.suite-id in setup job")
        (assert-truthy (not ($yml | str contains "needs.setup.outputs.suite-id"))
            "ci-matrix.yml has no dot-notation needs.setup.outputs.suite-id")
    ]
}

def test-run-cell-iterates-all-deps [] {
    test-log "\n[test-run-cell-iterates-all-deps]"
    let yml = (build-run-cell-yml)
    [
        (assert-truthy ($yml | str contains "nu scripts/ocmts.nu ci download-prereqs")
            "ci-run-cell.yml prereq step uses public download-prereqs command")
        (assert-truthy ($yml | str contains "--deps")
            "ci-run-cell.yml download-prereqs step passes --deps flag")
        (assert-truthy ($yml | str contains "--deps \"${{ inputs['cell-depends-on'] }}\"")
            "ci-run-cell.yml download-prereqs step binds cell-depends-on to --deps")
    ]
}

def test-run-cell-download-uses-current-run-id [] {
    test-log "\n[test-run-cell-download-uses-current-run-id]"
    let yml = (build-run-cell-yml)
    [
        (assert-truthy ($yml | str contains "--run-id \"${{ github.run_id }}\"")
            "ci-run-cell.yml prereq download pins to current run via github.run_id")
        (assert-truthy ($yml | str contains "GH_TOKEN: ${{ github.token }}")
            "ci-run-cell.yml prereq download step has GH_TOKEN")
    ]
}

# Regression: one-party cells must not receive empty receiver flags.
# ci-run-cell.yml passed --receiver-platform / --receiver-version unconditionally,
# causing emit-blocked (and services-up-run) to see empty receiver args for
# one-party scenarios. The fix must use a conditional guard pattern instead.
def test-run-cell-one-party-receiver-flag-guard [] {
    test-log "\n[test-run-cell-one-party-receiver-flag-guard]"
    let run_cell_yml = (build-run-cell-yml)
    [
        (assert-truthy (not ($run_cell_yml | str contains "--receiver-platform \"${{ inputs['receiver-platform'] }}\" \\"))
            "ci-run-cell.yml does not unconditionally pass --receiver-platform (one-party guard required)")
        (assert-truthy (not ($run_cell_yml | str contains "--receiver-version \"${{ inputs['receiver-version'] }}\" \\"))
            "ci-run-cell.yml does not unconditionally pass --receiver-version (one-party guard required)")
    ]
}

def test-action-refs-from-ssot [] {
    test-log "\n[test-action-refs-from-ssot]"
    let real_root = ($SUITE_PATH | path dirname | path dirname | path dirname | path dirname)
    let wf = (open ($real_root | path join "config/ci/workflows.nuon"))
    let gh = $wf.github
    let checkout = ($gh.action_checkout? | default "actions/checkout@v6")
    let upload = ($gh.action_upload_artifact? | default "actions/upload-artifact@v7")
    let download = ($gh.action_download_artifact? | default "actions/download-artifact@v7")
    let run_cell_yml = (build-run-cell-yml)
    let run_wave_yml = (build-run-wave-yml)
    let rules = fixture-rules
    let prereqs = fixture-prereqs
    let plan = (plan-suite $rules $prereqs (fixture-flow-caps) {})
    let matrix_yml = (build-ci-matrix-yml $plan)
    [
        (assert-truthy (not ($run_cell_yml | str contains "actions/checkout@v4"))
            "ci-run-cell.yml does not hardcode actions/checkout@v4")
        (assert-truthy ($run_cell_yml | str contains $checkout)
            "ci-run-cell.yml uses checkout action from config")
        (assert-truthy (not ($run_cell_yml | str contains "actions/upload-artifact@v4"))
            "ci-run-cell.yml does not hardcode actions/upload-artifact@v4")
        (assert-truthy ($run_cell_yml | str contains $upload)
            "ci-run-cell.yml uses upload-artifact action from config")
        (assert-truthy ($run_wave_yml | str contains $checkout)
            "ci-run-wave.yml uses checkout action from config")
        (assert-truthy ($matrix_yml | str contains $checkout)
            "ci-matrix.yml uses checkout action from config")
        (assert-truthy ($matrix_yml | str contains $download)
            "ci-matrix.yml uses download-artifact action from config")
        (assert-truthy (not ($matrix_yml | str contains "actions/download-artifact@v4"))
            "ci-matrix.yml does not hardcode actions/download-artifact@v4")
    ]
}

def test-upload-excludes-mitm-conf [] {
    test-log "\n[test-upload-excludes-mitm-conf]"
    let run_cell_yml = (build-run-cell-yml)
    [
        (assert-truthy ($run_cell_yml | str contains "!artifacts/**/mitm/conf/**")
            "ci-run-cell.yml upload excludes artifacts/**/mitm/conf/** via negated pattern")
        (assert-truthy ($run_cell_yml | str contains "artifacts/")
            "ci-run-cell.yml upload still includes artifacts/ root")
    ]
}

def test-run-cell-no-suite-kind-suite [] {
    test-log "\n[test-run-cell-no-suite-kind-suite]"
    let run_cell_yml = (build-run-cell-yml)
    [
        (assert-truthy (not ($run_cell_yml | str contains "--suite-kind suite"))
            "ci-run-cell.yml Run cell step does not pass --suite-kind suite (each cell job has no local suite record)")
    ]
}

def test-run-cell-has-prepull-runtime-images [] {
    test-log "\n[test-run-cell-has-prepull-runtime-images]"
    let run_cell_yml = (build-run-cell-yml)
    let prepull_pos = ($run_cell_yml | str index-of "Pre-pull runtime images")
    let run_pos = ($run_cell_yml | str index-of "Run cell (when no prerequisite failure)")
    [
        (assert-truthy ($run_cell_yml | str contains "Pre-pull runtime images")
            "ci-run-cell.yml has Pre-pull runtime images step")
        (assert-truthy ($run_cell_yml | str contains "nu scripts/ocmts.nu services list-cell-images")
            "ci-run-cell.yml pre-pull step calls services list-cell-images")
        (assert-truthy ($prepull_pos < $run_pos)
            "Pre-pull runtime images step appears before Run cell step")
    ]
}

def test-run-wave-display-name-in-matrix [] {
    test-log "\n[test-run-wave-display-name-in-matrix]"
    let run_wave_yml = (build-run-wave-yml)
    [
        (assert-truthy ($run_wave_yml | str contains "name: test ${{ matrix.wave_index }}")
            "ci-run-wave.yml matrix job name uses wave_index for unique per-row disambiguation")
        (assert-truthy (not ($run_wave_yml | str contains "    name: ${{ matrix.display_name }}"))
            "ci-run-wave.yml matrix job-level name: does not repeat display_name (no 4-space name: display_name line)")
    ]
}

def test-run-wave-display-name-position [] {
    test-log "\n[test-run-wave-display-name-position]"
    let real_root = ($SUITE_PATH | path dirname | path dirname | path dirname | path dirname)
    let wf = (open ($real_root | path join "config/ci/workflows.nuon"))
    let run_cell = ($wf.github.filenames.run_cell? | default "ci-run-cell.yml")
    let run_wave_yml = (build-run-wave-yml)
    let name_pos = ($run_wave_yml | str index-of "    name: test ${{ matrix.wave_index }}")
    let uses_pos = ($run_wave_yml | str index-of $"    uses: ./.github/workflows/($run_cell)")
    # Use a specific substring to locate the matrix job's with: block
    # (avoids matching the 8-space `with:` inside load-cells steps).
    let with_pos = ($run_wave_yml | str index-of "    with:\n      display-name:")
    [
        (assert-truthy ($name_pos < $uses_pos)
            "wave job name: test appears before uses: in ci-run-wave.yml")
        (assert-truthy ($name_pos < $with_pos)
            "wave job name: test is not inside the with: block in ci-run-wave.yml")
    ]
}

def test-run-cell-display-name [] {
    test-log "\n[test-run-cell-display-name]"
    let run_wave_yml = (build-run-wave-yml)
    let run_cell_yml = (build-run-cell-yml)
    [
        (assert-truthy ($run_wave_yml | str contains "display-name: ${{ matrix.display_name }}")
            "ci-run-wave.yml passes display-name: ${{ matrix.display_name }} in with: block to ci-run-cell.yml")
        (assert-truthy ($run_cell_yml | str contains "display-name:")
            "ci-run-cell.yml declares display-name workflow_call input")
        (assert-truthy ($run_cell_yml | str contains "name: ${{ inputs['display-name'] }}")
            "ci-run-cell.yml sets name: ${{ inputs['display-name'] }} on job run-cell")
    ]
}

def test-matrix-trigger-policy [] {
    test-log "\n[test-matrix-trigger-policy]"
    let rules = fixture-rules
    let prereqs = fixture-prereqs
    let plan = (plan-suite $rules $prereqs (fixture-flow-caps) {})
    let yml = (build-ci-matrix-yml $plan)
    [
        (assert-truthy ($yml | str contains "pull_request:")
            "ci-matrix.yml contains pull_request: trigger")
        (assert-truthy ($yml | str contains "workflow_dispatch:")
            "ci-matrix.yml contains workflow_dispatch: trigger")
        (assert-truthy ($yml | str contains "push:")
            "ci-matrix.yml contains push: trigger")
        (assert-truthy ($yml | str contains "branches: ['main']")
            "ci-matrix.yml push trigger uses branches: ['main']")
        (assert-truthy (not ($yml | str contains "branches: ['**']"))
            "ci-matrix.yml push trigger does not use branches: ['**']")
    ]
}

# Prove the run.cell.filename seam: overriding filenames.run_cell in
# config/ci/workflows.nuon must flow through to the rendered ci-run-wave.yml.
def test-run-wave-run-cell-filename-seam [] {
    test-log "\n[test-run-wave-run-cell-filename-seam]"
    let real_root = ($SUITE_PATH | path dirname | path dirname | path dirname | path dirname)
    with-tmp-dir {|tmp|
        mkdir ($tmp | path join "config/ci")
        cp ($real_root | path join "config/ci/toolchain.nuon") ($tmp | path join "config/ci/toolchain.nuon")
        let wf = (open ($real_root | path join "config/ci/workflows.nuon"))
        let custom_wf = ($wf | update github.filenames.run_cell "custom-run-cell.yml")
        ($custom_wf | to nuon) | save --force ($tmp | path join "config/ci/workflows.nuon")
        mkdir ($tmp | path join "scripts/lib/ci")
        cp --recursive ($real_root | path join "scripts/lib/ci/blueprints") ($tmp | path join "scripts/lib/ci/blueprints")
        with-env {OCMTS_ROOT: $tmp} {
            let yml = (build-run-wave-yml)
            [
                (assert-truthy ($yml | str contains "./.github/workflows/custom-run-cell.yml")
                    "build-run-wave-yml uses run_cell filename from config seam (not hardcoded)")
            ]
        }
    }
}

def main [] {
    test-log "=== CI workflow-contract tests ==="
    let results = (
        (test-blocked-output-check)
        | append (test-matrix-calls-run-wave)
        | append (test-run-wave-calls-run-cell)
        | append (test-run-wave-properties)
        | append (test-cells-path-in-matrix)
        | append (test-load-cells-job-in-run-wave)
        | append (test-run-wave-nushell-load-cells)
        | append (test-hardened-cell-expressions)
        | append (test-hardened-wave-expressions)
        | append (test-hardened-matrix-expressions)
        | append (test-run-cell-iterates-all-deps)
        | append (test-run-cell-download-uses-current-run-id)
        | append (test-run-cell-one-party-receiver-flag-guard)
        | append (test-action-refs-from-ssot)
        | append (test-upload-excludes-mitm-conf)
        | append (test-run-cell-no-suite-kind-suite)
        | append (test-run-cell-has-prepull-runtime-images)
        | append (test-run-wave-display-name-in-matrix)
        | append (test-run-wave-display-name-position)
        | append (test-run-cell-display-name)
        | append (test-matrix-trigger-policy)
        | append (test-run-wave-run-cell-filename-seam)
    ) | flatten
    run-suite "ci/workflow-contract" $SUITE_PATH $results
}
