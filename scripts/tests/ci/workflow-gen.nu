# Workflow-generator core invariant tests.
# Covers: baked ids, timestamps, placeholder rendering, job ordering,
# determinism, no-wave jobs, top-level YAML properties.
# Run: nu scripts/tests/ci/workflow-gen.nu
# Returns exit 0 on all pass, exit 1 with details on failure.

const SUITE_PATH = path self

use ../../lib/ci/planner.nu [plan-suite]
use ../../lib/ci/workflow-gen.nu [
    build-ci-matrix-yml
    build-run-wave-yml
    build-run-cell-yml
    build-ci-site-yml
]
use ../../lib/ci/template-renderer.nu [render-template]
use ../../lib/tests/assert.nu *
use ../../lib/tests/runner.nu [run-suite]
use ./fixtures.nu [fixture-rules fixture-prereqs fixture-flow-caps]

# ---- tests ----

def test-workflow-no-baked-ids [] {
    test-log "\n[test-workflow-no-baked-ids]"
    let rules = fixture-rules
    let prereqs = fixture-prereqs
    let plan = (plan-suite $rules $prereqs (fixture-flow-caps) {})
    let yml = (build-ci-matrix-yml $plan)

    # suite_id (a timestamp+uuid) must NOT appear in the generated YAML.
    # It is resolved at workflow runtime via the setup job output instead.
    let suite_id_baked = ($yml | str contains $plan.suite_id)

    # No per-cell execution_id should be embedded.
    let exec_ids_baked = ($plan.cells | any {|c| $yml | str contains $c.execution_id})

    # The runtime suite-id output reference must be present (bracket notation).
    let has_setup_output = ($yml | str contains "needs.setup.outputs['suite-id']")

    # The setup job itself must be present.
    let has_setup_job = ($yml | str contains "  setup:")

    # Each cell job must depend on setup.
    let all_cells_need_setup = ($plan.cells | all {|c|
        let jname = (
            $c.cell_id
            | str replace --all "__" "_"
            | str replace --all "-" "_"
        )
        $yml | str contains $"needs: [setup"
    })

    [
        (assert-truthy (not $suite_id_baked)
            "generated YAML does not contain baked suite_id")
        (assert-truthy (not $exec_ids_baked)
            "generated YAML does not contain baked execution_ids")
        (assert-truthy $has_setup_output
            "generated YAML references needs.setup.outputs['suite-id'] (bracket notation)")
        (assert-truthy $has_setup_job
            "generated YAML contains setup job")
        (assert-truthy $all_cells_need_setup
            "all cell jobs declare needs including setup")
    ]
}

def test-no-generated-timestamp [] {
    test-log "\n[test-no-generated-timestamp]"
    let rules = fixture-rules
    let prereqs = fixture-prereqs
    let plan = (plan-suite $rules $prereqs (fixture-flow-caps) {})
    let matrix_yml = (build-ci-matrix-yml $plan)
    let run_cell_yml = (build-run-cell-yml)
    let ci_site_yml = (build-ci-site-yml)
    [
        (assert-truthy (not ($matrix_yml | str contains "Generated at:"))
            "ci-matrix.yml has no 'Generated at:' timestamp")
        (assert-truthy (not ($run_cell_yml | str contains "Generated at:"))
            "ci-run-cell.yml has no 'Generated at:' timestamp")
        (assert-truthy (not ($ci_site_yml | str contains "Generated at:"))
            "ci-site.yml has no 'Generated at:' timestamp")
    ]
}

def test-setup-failure-guard [] {
    test-log "\n[test-setup-failure-guard]"
    let rules = fixture-rules
    let prereqs = fixture-prereqs
    let plan = (plan-suite $rules $prereqs (fixture-flow-caps) {})
    let yml = (build-ci-matrix-yml $plan)
    [
        (assert-truthy ($yml | str contains "always() && needs.setup.result == 'success'")
            "cell jobs use 'always() && needs.setup.result == success' condition")
    ]
}

def test-nushell-version-from-config [] {
    test-log "\n[test-nushell-version-from-config]"
    let rules = fixture-rules
    let prereqs = fixture-prereqs
    let plan = (plan-suite $rules $prereqs (fixture-flow-caps) {})
    let matrix_yml = (build-ci-matrix-yml $plan)
    let run_cell_yml = (build-run-cell-yml)
    [
        (assert-truthy ($matrix_yml | str contains "version: '0.108.0'")
            "ci-matrix.yml uses pinned nushell version 0.108.0")
        (assert-truthy ($run_cell_yml | str contains "version: '0.108.0'")
            "ci-run-cell.yml uses pinned nushell version 0.108.0")
        (assert-truthy (not ($matrix_yml | str contains "version: '*'"))
            "ci-matrix.yml does not use version: '*'")
        (assert-truthy (not ($matrix_yml | str contains "version: \"*\""))
            "ci-matrix.yml does not use version: \"*\"")
        (assert-truthy (not ($run_cell_yml | str contains "version: '*'"))
            "ci-run-cell.yml does not use version: '*'")
        (assert-truthy (not ($run_cell_yml | str contains "version: \"*\""))
            "ci-run-cell.yml does not use version: \"*\"")
    ]
}

def test-no-unresolved-placeholders [] {
    test-log "\n[test-no-unresolved-placeholders]"
    let rules = fixture-rules
    let prereqs = fixture-prereqs
    let plan = (plan-suite $rules $prereqs (fixture-flow-caps) {})
    let matrix_yml = (build-ci-matrix-yml $plan)
    let run_wave_yml = (build-run-wave-yml)
    let run_cell_yml = (build-run-cell-yml)
    let ci_site_yml = (build-ci-site-yml)
    let matrix_placeholders = ($matrix_yml | parse --regex '\{\{placeholder:([^}]+)\}\}' | length)
    let run_wave_placeholders = ($run_wave_yml | parse --regex '\{\{placeholder:([^}]+)\}\}' | length)
    let run_cell_placeholders = ($run_cell_yml | parse --regex '\{\{placeholder:([^}]+)\}\}' | length)
    let ci_site_placeholders = ($ci_site_yml | parse --regex '\{\{placeholder:([^}]+)\}\}' | length)
    [
        (assert-eq $matrix_placeholders 0
            "ci-matrix.yml has no unresolved {{placeholder:...}} tokens")
        (assert-eq $run_wave_placeholders 0
            "ci-run-wave.yml has no unresolved {{placeholder:...}} tokens")
        (assert-eq $run_cell_placeholders 0
            "ci-run-cell.yml has no unresolved {{placeholder:...}} tokens")
        (assert-eq $ci_site_placeholders 0
            "ci-site.yml has no unresolved {{placeholder:...}} tokens")
    ]
}

def test-render-template-fails-on-unresolved [] {
    test-log "\n[test-render-template-fails-on-unresolved]"
    let caught = (try {
        render-template "hello {{placeholder:missing}}" {}
        false
    } catch {
        true
    })
    [
        (assert-truthy $caught "render-template raises error on unresolved placeholder")
    ]
}

def test-render-template-replaces-all [] {
    test-log "\n[test-render-template-replaces-all]"
    let result = (render-template "a={{placeholder:a}}, b={{placeholder:b}}" {a: "1", b: "2"})
    [
        (assert-eq $result "a=1, b=2" "render-template replaces all placeholders")
    ]
}

def test-cell-visual-job-order [] {
    test-log "\n[test-cell-visual-job-order]"
    let rules = fixture-rules
    let prereqs = fixture-prereqs
    let plan = (plan-suite $rules $prereqs (fixture-flow-caps) {})
    let yml = (build-ci-matrix-yml $plan)

    # Flow-based generator emits one job per flow in job_order visual order.
    # login: must appear before share-with: in the generated YAML.
    let login_pos = ($yml | str index-of "  login:")
    let share_with_pos = ($yml | str index-of "  share-with:")

    [
        (assert-truthy (
            ($login_pos != -1) and ($share_with_pos != -1) and ($login_pos < $share_with_pos)
        ) "login flow job appears before share-with flow job in generated YAML")
    ]
}

def test-generated-header-command [] {
    test-log "\n[test-generated-header-command]"
    let rules = fixture-rules
    let prereqs = fixture-prereqs
    let plan = (plan-suite $rules $prereqs (fixture-flow-caps) {})
    let matrix_yml = (build-ci-matrix-yml $plan)
    let run_wave_yml = (build-run-wave-yml)
    let run_cell_yml = (build-run-cell-yml)
    let ci_site_yml = (build-ci-site-yml)
    [
        (assert-truthy ($matrix_yml | str contains "nu scripts/ocmts.nu ci workflows generate github")
            "ci-matrix.yml header uses new generator command")
        (assert-truthy ($run_wave_yml | str contains "nu scripts/ocmts.nu ci workflows generate github")
            "ci-run-wave.yml header uses new generator command")
        (assert-truthy ($run_cell_yml | str contains "nu scripts/ocmts.nu ci workflows generate github")
            "ci-run-cell.yml header uses new generator command")
        (assert-truthy ($ci_site_yml | str contains "nu scripts/ocmts.nu ci workflows generate github")
            "ci-site.yml header uses new generator command")
    ]
}

def test-workflow-deterministic [] {
    test-log "\n[test-workflow-deterministic]"
    let rules = fixture-rules
    let prereqs = fixture-prereqs
    let plan1 = (plan-suite $rules $prereqs (fixture-flow-caps) {} --suite-id "fixed-suite-id")
    let plan2 = (plan-suite $rules $prereqs (fixture-flow-caps) {} --suite-id "fixed-suite-id")
    let yml1 = (build-ci-matrix-yml $plan1)
    let yml2 = (build-ci-matrix-yml $plan2)
    let rw_yml1 = (build-run-wave-yml)
    let rw_yml2 = (build-run-wave-yml)
    let rc_yml1 = (build-run-cell-yml)
    let rc_yml2 = (build-run-cell-yml)
    let cs_yml1 = (build-ci-site-yml)
    let cs_yml2 = (build-ci-site-yml)
    [
        (assert-eq $yml1 $yml2 "ci-matrix.yml generation is deterministic")
        (assert-eq $rw_yml1 $rw_yml2 "ci-run-wave.yml generation is deterministic")
        (assert-eq $rc_yml1 $rc_yml2 "ci-run-cell.yml generation is deterministic")
        (assert-eq $cs_yml1 $cs_yml2 "ci-site.yml generation is deterministic")
    ]
}

def test-flow-based-no-wave-jobs [] {
    test-log "\n[test-flow-based-no-wave-jobs]"
    let rules = fixture-rules
    let prereqs = fixture-prereqs
    let plan = (plan-suite $rules $prereqs (fixture-flow-caps) {})
    let yml = (build-ci-matrix-yml $plan)
    [
        (assert-truthy (not ($yml | str contains "wave_0:"))
            "generated ci-matrix.yml does not contain wave_0 job")
        (assert-truthy (not ($yml | str contains "wave_1:"))
            "generated ci-matrix.yml does not contain wave_1 job")
        (assert-truthy ($yml | str contains "  login:")
            "generated ci-matrix.yml contains login flow job")
        (assert-truthy ($yml | str contains "  share-with:")
            "generated ci-matrix.yml contains share-with flow job")
    ]
}

def test-wave-gen-yaml-properties [] {
    test-log "\n[test-wave-gen-yaml-properties]"
    let rules = fixture-rules
    let prereqs = fixture-prereqs
    let plan = (plan-suite $rules $prereqs (fixture-flow-caps) {})
    let yml = (build-ci-matrix-yml $plan)
    let run_wave_yml = (build-run-wave-yml)
    let ci_site_pos = ($yml | str index-of "  ci-site:")
    let before_ci_site = ($yml | str substring 0..$ci_site_pos)
    [
        (assert-truthy ($run_wave_yml | str contains "fail-fast: false")
            "ci-run-wave.yml has strategy.fail-fast: false")
        (assert-truthy ($yml | str contains "--archive")
            "aggregate job runs aggregate command with --archive flag")
        (assert-truthy ($yml | str contains "github.ref == 'refs/heads/main'")
            "ci-site job is gated on main branch")
        (assert-truthy (not ($before_ci_site | str contains "github.ref"))
            "aggregate job is NOT gated on main branch (no github.ref before ci-site)")
    ]
}

def main [] {
    test-log "=== CI workflow-gen tests ==="
    let results = (
        (test-workflow-no-baked-ids)
        | append (test-no-generated-timestamp)
        | append (test-setup-failure-guard)
        | append (test-nushell-version-from-config)
        | append (test-no-unresolved-placeholders)
        | append (test-render-template-fails-on-unresolved)
        | append (test-render-template-replaces-all)
        | append (test-cell-visual-job-order)
        | append (test-generated-header-command)
        | append (test-workflow-deterministic)
        | append (test-flow-based-no-wave-jobs)
        | append (test-wave-gen-yaml-properties)
    ) | flatten
    run-suite "ci/workflow-gen" $SUITE_PATH $results
}
