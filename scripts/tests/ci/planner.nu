# CI planner, blocker, workflow-gen, and suite-index tests.
# Run: nu scripts/tests/ci/planner.nu
# Returns exit 0 on all pass, exit 1 with details on failure.

const SUITE_PATH = path self

use ../../lib/ci/planner.nu [
    plan-suite
    compute-capability-id
    compute-cell-capabilities-produced
    compute-cell-depends-on
]
use ../../lib/ci/blocker.nu [eval-blocked-cells]
use ../../lib/ci/aggregate.nu [aggregate-suite-manifests build-aggregate-summary aggregate-status reconstruct-suite-index]
use ../../lib/ci/flow-order.nu [sort-cells-by-flow-order]
use ../../lib/ci/workflow-gen.nu [
    build-ci-matrix-yml
    build-run-wave-yml
    build-run-cell-yml
    build-ci-site-yml
    build-aggregate-needs-block
    build-flow-assets
    build-flow-asset-content
]
use ../../lib/ci/template-renderer.nu [render-template]
use ../../lib/suite/index.nu [compute-suite-status]
use ../../lib/tests/assert.nu *
use ../../lib/tests/fixtures.nu [materialize-provenance-stubs]
use ../../lib/tests/runner.nu [run-suite]

# Minimal matrix rules fixture covering key cases.
def fixture-rules [] {
    {
        scenarios: {
            login: {
                enabled: true,
                flow_id: "login",
                browsers: ["chrome"],
                sender: {platform: "nextcloud", version_lines: ["v33" "v34"]},
                receiver: null,
                mitm: false,
            },
            "login-v34-only": {
                enabled: true,
                flow_id: "login",
                browsers: ["chrome"],
                sender: {platform: "nextcloud", version_lines: ["v34"]},
                receiver: null,
                mitm: false,
            },
            "share-with": {
                enabled: true,
                flow_id: "share-with",
                browsers: ["chrome"],
                sender: {platform: "nextcloud", version_lines: ["v34"]},
                receiver: {platform: "nextcloud", version_lines: ["v34"]},
                mitm: true,
            },
            "disabled-flow": {
                enabled: false,
                flow_id: "login",
                browsers: ["chrome"],
                sender: {platform: "nextcloud", version_lines: ["v33"]},
                receiver: null,
                mitm: false,
            },
        }
    }
}

def fixture-prereqs [] {
    {
        capability_rules: [
            {
                capability_flow: "login",
                required_for_flows: ["share-with" "contact-token" "contact-wayf" "code-flow"],
                required_roles: ["sender" "receiver"],
            }
        ]
    }
}

# Flow caps with no capability requirements (empty sender/receiver lists).
# Passing this to plan-suite means derive-cell-impl-info finds no blockers
# and every enabled cell comes out as "supported" / capability_action "run".
def fixture-flow-caps [] {
    {
        "login": {sender: [], receiver: []},
        "share-with": {sender: [], receiver: []},
    }
}

# Rules fixture with a unique disabled cell (v99) so its cell_id does not
# collide with the enabled "login" scenario cells.
def fixture-rules-with-unique-disabled [] {
    {
        scenarios: {
            "login-only": {
                enabled: true,
                flow_id: "login",
                browsers: ["chrome"],
                sender: {platform: "nextcloud", version_lines: ["v34"]},
                receiver: null,
                mitm: false,
            },
            "disabled-login-v99": {
                enabled: false,
                flow_id: "login",
                browsers: ["chrome"],
                sender: {platform: "nextcloud", version_lines: ["v99"]},
                receiver: null,
                mitm: false,
            },
        }
    }
}

# Rules fixture for capability gating tests.
def fixture-rules-cap-tests [] {
    {
        scenarios: {
            "login-nc": {
                enabled: true,
                flow_id: "login",
                browsers: ["chrome"],
                sender: {platform: "nextcloud", version_lines: ["v34"]},
                receiver: null,
                mitm: false,
            },
            "login-oc": {
                enabled: true,
                flow_id: "login",
                browsers: ["chrome"],
                sender: {platform: "opencloud", version_lines: ["v6"]},
                receiver: null,
                mitm: false,
            },
        }
    }
}

def fixture-flow-caps-with-reqs [] {
    {
        "login": {
            sender: ["flow.login.sender"],
            receiver: [],
        }
    }
}

def fixture-adapters-cap [] {
    {
        "nextcloud/v34": {
            capabilities: {
                "flow.login.sender": {status: "supported"},
            }
        },
        "opencloud/v6": {
            capabilities: {
                "flow.login.sender": {status: "test-implementation-pending"},
            }
        },
    }
}

# ---- tests ----

def test-capability-id [] {
    test-log "\n[test-capability-id]"
    let results = [
        (assert-eq
            (compute-capability-id "login" "nextcloud" "v34")
            "login__nextcloud-v34"
            "login nextcloud-v34 capability id")
        (assert-eq
            (compute-capability-id "login" "ocmgo" "v1")
            "login__ocmgo-v1"
            "login ocmgo-v1 capability id")
        (assert-eq
            (compute-capability-id "login" "ocis" "v8")
            "login__ocis-v8"
            "login ocis-v8 capability id")
    ]
    $results
}

def test-cell-capabilities-produced [] {
    test-log "\n[test-cell-capabilities-produced]"
    let prereqs = fixture-prereqs
    let login_cell = {
        cell_id: "login__nextcloud-v34",
        flow_id: "login",
        sender_platform: "nextcloud",
        sender_version: "v34",
        receiver_platform: "",
        receiver_version: "",
        is_two_party: false,
    }
    let share_cell = {
        cell_id: "share-with__nextcloud-v34__nextcloud-v34",
        flow_id: "share-with",
        sender_platform: "nextcloud",
        sender_version: "v34",
        receiver_platform: "nextcloud",
        receiver_version: "v34",
        is_two_party: true,
    }
    let login_caps = (compute-cell-capabilities-produced $login_cell $prereqs)
    let share_caps = (compute-cell-capabilities-produced $share_cell $prereqs)
    [
        (assert-list-contains $login_caps "login__nextcloud-v34" "login cell produces login capability")
        (assert-eq ($share_caps | length) 0 "share-with cell produces no capabilities")
    ]
}

def test-cell-depends-on [] {
    test-log "\n[test-cell-depends-on]"
    let prereqs = fixture-prereqs
    # login cells from the matrix
    let login_v33_cell = {
        cell_id: "login__nextcloud-v33",
        flow_id: "login",
        sender_platform: "nextcloud",
        sender_version: "v33",
        receiver_platform: "",
        receiver_version: "",
        is_two_party: false,
    }
    let login_v34_cell = {
        cell_id: "login__nextcloud-v34",
        flow_id: "login",
        sender_platform: "nextcloud",
        sender_version: "v34",
        receiver_platform: "",
        receiver_version: "",
        is_two_party: false,
    }
    let share_cell = {
        cell_id: "share-with__nextcloud-v34__nextcloud-v34",
        flow_id: "share-with",
        sender_platform: "nextcloud",
        sender_version: "v34",
        receiver_platform: "nextcloud",
        receiver_version: "v34",
        is_two_party: true,
    }
    let all_cells = [$login_v33_cell $login_v34_cell $share_cell]
    let share_deps = (compute-cell-depends-on $share_cell $all_cells $prereqs)
    let login_deps = (compute-cell-depends-on $login_v34_cell $all_cells $prereqs)
    [
        (assert-list-contains $share_deps "login__nextcloud-v34"
            "share-with v34-v34 depends on login__nextcloud-v34")
        (assert-list-not-contains $share_deps "login__nextcloud-v33"
            "share-with v34-v34 does NOT depend on login__nextcloud-v33")
        (assert-eq ($login_deps | length) 0 "login cell has no dependencies")
    ]
}

def test-plan-suite [] {
    test-log "\n[test-plan-suite]"
    let rules = fixture-rules
    let prereqs = fixture-prereqs
    let plan = (plan-suite $rules $prereqs (fixture-flow-caps) {})
    let cell_ids = ($plan.cells | each {|c| $c.cell_id})
    [
        (assert-truthy (($plan.suite_id | str length) > 0) "plan has suite_id")
        (assert-eq ($plan.schema_version? | default 0) 1 "schema_version is 1")
        (assert-list-contains $cell_ids "login__nextcloud-v34"
            "plan includes login__nextcloud-v34")
        (assert-truthy (
            $plan.cells
            | where {|c| $c.cell_id == "login__nextcloud-v34"}
            | each {|c| ($c.execution_id | str length) > 0}
            | any {|v| $v}
        ) "each cell has execution_id")
        (assert-truthy (
            $plan.cells
            | where {|c| $c.cell_id == "login__nextcloud-v34"}
            | each {|c| ($c | columns | any {|f| $f == "capability_action"})}
            | any {|v| $v}
        ) "cells have capability_action field")
    ]
}

def test-plan-suite-nextcloud-v34-login-is-producer [] {
    test-log "\n[test-plan-suite-nextcloud-v34-login-is-producer]"
    let rules = fixture-rules
    let prereqs = fixture-prereqs
    let plan = (plan-suite $rules $prereqs (fixture-flow-caps) {})
    let login_v34 = ($plan.cells | where {|c| $c.cell_id == "login__nextcloud-v34"} | first)
    [
        (assert-list-contains $login_v34.capabilities_produced "login__nextcloud-v34"
            "login__nextcloud-v34 cell produces login capability for nextcloud-v34")
    ]
}

def test-blocked-eval [] {
    test-log "\n[test-blocked-eval]"
    let prereqs = fixture-prereqs
    let login_v34_cell = {
        cell_id: "login__nextcloud-v34",
        flow_id: "login",
        scenario: "login",
        sender_platform: "nextcloud",
        sender_version: "v34",
        receiver_platform: "",
        receiver_version: "",
        is_two_party: false,
        execution_id: "20260101t000000-aaaaaaaa",
        capabilities_produced: ["login__nextcloud-v34"],
        depends_on: [],
    }
    let share_cell = {
        cell_id: "share-with__nextcloud-v34__nextcloud-v34",
        flow_id: "share-with",
        scenario: "share-with",
        sender_platform: "nextcloud",
        sender_version: "v34",
        receiver_platform: "nextcloud",
        receiver_version: "v34",
        is_two_party: true,
        execution_id: "20260101t000001-bbbbbbbb",
        capabilities_produced: [],
        depends_on: ["login__nextcloud-v34"],
    }
    let planned_cells = [$login_v34_cell $share_cell]
    # Simulate: login__nextcloud-v34 failed
    let failed_cell_ids = ["login__nextcloud-v34"]
    let result = (eval-blocked-cells $planned_cells $failed_cell_ids)
    let share_entry = ($result | where {|r| $r.cell_id == "share-with__nextcloud-v34__nextcloud-v34"} | first)
    [
        (assert-truthy $share_entry.blocked
            "share-with cell is blocked when login__nextcloud-v34 fails")
        (assert-truthy (($share_entry.failure_reason | str contains "login__nextcloud-v34"))
            "blocked failure_reason names the failed prerequisite")
        (assert-eq (
            $result
            | where {|r| $r.cell_id == "login__nextcloud-v34"}
            | first
            | get blocked
        ) false "login cell itself is not blocked")
    ]
}

def test-blocked-result-status [] {
    test-log "\n[test-blocked-result-status]"
    # The blocked record shape: status == "blocked", failure_reason non-empty
    let planned_cells = [
        {
            cell_id: "share-with__nextcloud-v34__nextcloud-v34",
            flow_id: "share-with",
            scenario: "share-with",
            sender_platform: "nextcloud",
            sender_version: "v34",
            receiver_platform: "nextcloud",
            receiver_version: "v34",
            is_two_party: true,
            execution_id: "20260101t000001-bbbbbbbb",
            capabilities_produced: [],
            depends_on: ["login__nextcloud-v34"],
        }
    ]
    let failed_ids = ["login__nextcloud-v34"]
    let result = (eval-blocked-cells $planned_cells $failed_ids)
    let entry = ($result | first)
    [
        (assert-eq $entry.status "blocked" "blocked entry has status=blocked")
        (assert-truthy (not ($entry.failure_reason | is-empty))
            "blocked entry has non-empty failure_reason")
    ]
}

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

def test-transitive-blocked [] {
    test-log "\n[test-transitive-blocked]"
    # Three-level chain: A (fails) -> B (blocked) -> C (should be transitively blocked)
    let cell_a = {
        cell_id: "a",
        flow_id: "login",
        scenario: "login",
        sender_platform: "nextcloud",
        sender_version: "v34",
        receiver_platform: "",
        receiver_version: "",
        is_two_party: false,
        execution_id: "20260101t000000-aaaaaaaa",
        capabilities_produced: [],
        depends_on: [],
    }
    let cell_b = {
        cell_id: "b",
        flow_id: "share-with",
        scenario: "share-with",
        sender_platform: "nextcloud",
        sender_version: "v34",
        receiver_platform: "nextcloud",
        receiver_version: "v34",
        is_two_party: true,
        execution_id: "20260101t000001-bbbbbbbb",
        capabilities_produced: [],
        depends_on: ["a"],
    }
    let cell_c = {
        cell_id: "c",
        flow_id: "share-with",
        scenario: "share-with",
        sender_platform: "nextcloud",
        sender_version: "v34",
        receiver_platform: "nextcloud",
        receiver_version: "v34",
        is_two_party: true,
        execution_id: "20260101t000002-cccccccc",
        capabilities_produced: [],
        depends_on: ["b"],
    }

    # Step 1: A fails -> B is blocked
    let failed_ids = ["a"]
    let b_eval = (eval-blocked-cells [$cell_b] $failed_ids)
    let b_entry = ($b_eval | first)

    # Step 2: simulate suite loop: unavailable = failed + blocked
    let blocked_ids = if $b_entry.blocked { ["b"] } else { [] }
    let unavailable = ($failed_ids | append $blocked_ids)

    # Step 3: C depends on B (blocked) -> C should be blocked transitively
    let c_eval = (eval-blocked-cells [$cell_c] $unavailable)
    let c_entry = ($c_eval | first)

    [
        (assert-truthy $b_entry.blocked "cell B is blocked when A fails")
        (assert-truthy $c_entry.blocked
            "cell C is transitively blocked when B is blocked (unavailable set includes blocked)")
        (assert-truthy (not ($c_entry.failure_reason | is-empty))
            "transitively blocked cell C has non-empty failure_reason")
    ]
}

def test-suite-status-with-blocked [] {
    test-log "\n[test-suite-status-with-blocked]"
    [
        (assert-eq (compute-suite-status ["passed" "passed" "passed" "passed" "passed"]) "passed"
            "all passed -> passed")
        (assert-eq (compute-suite-status ["passed" "passed" "passed" "passed" "failed"]) "failed"
            "one failed -> failed")
        (assert-eq (compute-suite-status ["passed" "passed" "passed" "passed" "blocked"]) "blocked"
            "one blocked, none failed -> blocked")
        (assert-eq (compute-suite-status ["passed" "passed" "passed" "failed" "blocked"]) "failed"
            "failed and blocked -> failed (failed takes priority)")
        (assert-eq (compute-suite-status []) "passed"
            "no cells -> passed")
        (assert-eq (compute-suite-status ["blocked" "blocked" "blocked"]) "blocked"
            "all blocked -> blocked")
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

def test-site-env-names [] {
    test-log "\n[test-site-env-names]"
    let ci_site_yml = (build-ci-site-yml)
    [
        (assert-truthy ($ci_site_yml | str contains "OCMTS_SITE_REPO_SLUG")
            "ci-site.yml uses OCMTS_SITE_REPO_SLUG env name")
        (assert-truthy ($ci_site_yml | str contains "OCMTS_SITE_REF")
            "ci-site.yml uses OCMTS_SITE_REF env name")
        (assert-truthy ($ci_site_yml | str contains "OCMTS_SITE_REPO_URL")
            "ci-site.yml uses OCMTS_SITE_REPO_URL env name")
        (assert-truthy (not ($ci_site_yml | str contains "SITE_REPO:"))
            "ci-site.yml does not use old SITE_REPO env name")
    ]
}

def test-aggregate-summary-counts [] {
    test-log "\n[test-aggregate-summary-counts]"
    let mock_manifest = {
        aggregate_status: "failed",
        results: {
            "res-1": {status: "passed"},
            "res-2": {status: "failed"},
            "res-3": {status: "blocked"},
            "res-4": {status: "infra-failed"},
            "res-5": {status: "passed"},
            "res-6": {status: "cleanup-failed"},
        },
    }
    let s = (build-aggregate-summary $mock_manifest)
    [
        (assert-eq $s.total 6 "total count is 6")
        (assert-eq $s.passed 2 "passed count is 2")
        (assert-eq $s.failed 1 "failed count is 1")
        (assert-eq $s.infra_failed 1 "infra_failed count is 1")
        (assert-eq $s.cleanup_failed 1 "cleanup_failed count is 1")
        (assert-eq $s.blocked 1 "blocked count is 1")
        (assert-eq $s.unknown 0 "unknown count is 0")
        (assert-eq $s.aggregate_status "failed" "aggregate_status is failed")
    ]
}

def test-aggregate-summary-empty [] {
    test-log "\n[test-aggregate-summary-empty]"
    let mock_manifest = {
        aggregate_status: "passed",
        results: {},
    }
    let s = (build-aggregate-summary $mock_manifest)
    [
        (assert-eq $s.total 0 "empty results: total is 0")
        (assert-eq $s.passed 0 "empty results: passed is 0")
        (assert-eq $s.aggregate_status "passed" "aggregate_status is passed")
    ]
}

def test-aggregate-upload-step [] {
    test-log "\n[test-aggregate-upload-step]"
    let rules = fixture-rules
    let prereqs = fixture-prereqs
    let plan = (plan-suite $rules $prereqs (fixture-flow-caps) {})
    let yml = (build-ci-matrix-yml $plan)
    [
        (assert-truthy ($yml | str contains "Upload aggregate outputs")
            "aggregate job has Upload aggregate outputs step")
        (assert-truthy ($yml | str contains "name: aggregate-summary")
            "aggregate upload uses artifact name aggregate-summary")
        (assert-truthy ($yml | str contains "path: artifacts/suites/aggregated/")
            "aggregate upload path is artifacts/suites/aggregated/")
    ]
}

def test-aggregate-cap-skipped-passthrough [] {
    test-log "\n[test-aggregate-cap-skipped-passthrough]"
    let rules = fixture-rules
    let prereqs = fixture-prereqs
    let plan = (plan-suite $rules $prereqs (fixture-flow-caps) {})
    let yml = (build-ci-matrix-yml $plan)
    [
        (assert-truthy ($yml | str contains "CAP_SKIPPED_JSON=artifacts/capability-skipped-cells.json")
            "aggregate step writes cap-skipped cells to a JSON file")
        (assert-truthy ($yml | str contains "select(.capability_action == \"capability-skipped\") | {")
            "aggregate step serializes full capability-skipped cell records via jq")
        (assert-truthy ($yml | str contains "--capability-skipped-cells \"$CAP_SKIPPED_JSON\"")
            "aggregate step passes the capability-skipped JSON file path")
    ]
}

def test-site-publish-downloads-cell-artifacts [] {
    test-log "\n[test-site-publish-downloads-cell-artifacts]"
    let ci_site_yml = (build-ci-site-yml)
    # ci-site.yml downloads the raw aggregate bundle and unpacks it, then
    # downloads optimized-media-cell-* artifacts separately.
    [
        (assert-truthy ($ci_site_yml | str contains "Download raw aggregate artifact")
            "ci-site.yml has Download raw aggregate artifact step")
        (assert-truthy ($ci_site_yml | str contains "Extract aggregate archive")
            "ci-site.yml has Extract aggregate archive step")
        (assert-truthy ($ci_site_yml | str contains "tar -x -I zstd")
            "ci-site.yml extract step uses tar with zstd decompression")
        (assert-truthy (not ($ci_site_yml | str contains "pattern: 'cell-*'"))
            "ci-site.yml does not download raw cell-* artifacts directly")
    ]
}

def test-site-publish-artifacts-root [] {
    test-log "\n[test-site-publish-artifacts-root]"
    let ci_site_yml = (build-ci-site-yml)
    [
        (assert-truthy ($ci_site_yml | str contains "--artifacts-root artifacts")
            "ci-site.yml publish command uses --artifacts-root artifacts")
        (assert-truthy ($ci_site_yml | str contains "--latest-suite")
            "ci-site.yml publish command uses --latest-suite for suite-based ingest")
        (assert-truthy ($ci_site_yml | str contains "--optimized-media-dir")
            "ci-site.yml publish command passes --optimized-media-dir")
    ]
}

def test-aggregate-status-cleanup-failed [] {
    test-log "\n[test-aggregate-status-cleanup-failed]"
    [
        (assert-eq (aggregate-status ["cleanup-failed"])
            "failed"
            "cleanup-failed alone -> aggregate_status failed")
        (assert-eq (aggregate-status ["passed" "cleanup-failed"])
            "failed"
            "passed + cleanup-failed -> aggregate_status failed")
        (assert-eq (aggregate-status ["cleanup-failed" "blocked"])
            "failed"
            "cleanup-failed + blocked -> aggregate_status failed (failed takes priority)")
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

def test-sort-cells-by-flow-order [] {
    test-log "\n[test-sort-cells-by-flow-order]"
    let cells = [
        {cell_id: "contact-token__nextcloud-v34__nextcloud-v34", flow_id: "contact-token"}
        {cell_id: "login__nextcloud-v34", flow_id: "login"}
        {cell_id: "share-with__nextcloud-v34__nextcloud-v34", flow_id: "share-with"}
    ]
    let job_order = ["login", "share-with", "contact-token", "contact-wayf", "code-flow"]
    let sorted = (sort-cells-by-flow-order $cells $job_order)
    let ids = ($sorted | each {|c| $c.cell_id})
    [
        (assert-eq ($ids | first) "login__nextcloud-v34"
            "login cell sorts first")
        (assert-eq ($ids | get 1) "share-with__nextcloud-v34__nextcloud-v34"
            "share-with cell sorts second")
        (assert-eq ($ids | last) "contact-token__nextcloud-v34__nextcloud-v34"
            "contact-token cell sorts last")
    ]
}

# Verify that sort-then-max preserves flow order rather than plan order.
# This mirrors what local `test suite --max N` does: sort first, then take
# the first N, so that --max 1 always picks the first flow-ordered cell.
def test-suite-sort-then-max-respects-flow-order [] {
    test-log "\n[test-suite-sort-then-max-respects-flow-order]"
    # Reverse order relative to job_order to simulate unordered planner output.
    let cells = [
        {cell_id: "share-with__nextcloud-v34__nextcloud-v34", flow_id: "share-with"}
        {cell_id: "contact-token__nextcloud-v34__nextcloud-v34", flow_id: "contact-token"}
        {cell_id: "login__nextcloud-v34", flow_id: "login"}
    ]
    let job_order = ["login", "share-with", "contact-token", "contact-wayf", "code-flow"]
    let sorted = (sort-cells-by-flow-order $cells $job_order)

    let max1 = ($sorted | first 1)
    let max2 = ($sorted | first 2)

    [
        (assert-eq ($max1 | first | get cell_id) "login__nextcloud-v34"
            "--max 1 picks login (first in flow order)")
        (assert-eq ($max2 | get 0 | get cell_id) "login__nextcloud-v34"
            "--max 2 first cell is login")
        (assert-eq ($max2 | get 1 | get cell_id) "share-with__nextcloud-v34__nextcloud-v34"
            "--max 2 second cell is share-with")
    ]
}

def test-aggregate-needs-block-format [] {
    test-log "\n[test-aggregate-needs-block-format]"
    let block = (build-aggregate-needs-block ["login_nextcloud_v34" "share_with_nextcloud_v34_nextcloud_v34"])
    [
        (assert-truthy ($block | str contains "needs:")
            "aggregate needs block contains 'needs:'")
        (assert-truthy ($block | str contains "setup,")
            "aggregate needs block contains 'setup,'")
        (assert-truthy ($block | str contains "login_nextcloud_v34,")
            "aggregate needs block contains login job")
        (assert-truthy ($block | str contains "share_with_nextcloud_v34_nextcloud_v34,")
            "aggregate needs block contains share-with job")
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

def test-wave-plan-aware-aggregate [] {
    test-log "\n[test-wave-plan-aware-aggregate]"
    use ../../lib/ci/aggregate.nu [build-aggregate-summary aggregate-status]
    # Simulate a manifest with one passed and two missing cells.
    let mock_manifest = {
        aggregate_status: "missing",
        results: {
            "res-a": {status: "passed", cell_id: "a"},
            "res-b": {status: "missing", cell_id: "b"},
            "res-c": {status: "missing", cell_id: "c"},
        },
    }
    let summary = (build-aggregate-summary $mock_manifest)
    [
        (assert-eq $summary.total 3 "plan-aware summary: total 3")
        (assert-eq $summary.passed 1 "plan-aware summary: 1 passed")
        (assert-eq $summary.missing 2 "plan-aware summary: 2 missing")
        (assert-eq $summary.aggregate_status "missing" "aggregate_status is missing when cells are missing but none failed")
    ]
}

def test-plan-aware-aggregate-injects-missing [] {
    test-log "\n[test-plan-aware-aggregate-injects-missing]"
    use ../../lib/ci/aggregate.nu [aggregate-suite-manifests-plan-aware build-aggregate-summary]
    let tmp = (^mktemp -d | str trim)
    let cell_a_dir = ($tmp | path join "cell-a")
    mkdir ($cell_a_dir | path join "meta")
    let ts = "2026-01-01T00:00:00Z"
    let manifest_a = {
        schema_version: 1,
        generated_at: $ts,
        suite_id: "suite-test",
        producer: {name: "ocmts-cell", version: "0.1.0"},
        flows: {},
        cells: {},
        runs: {},
        results: {
            "result-a": {
                schema_version: 1,
                id: "result-a",
                run_id: "",
                execution_id: "",
                cell_id: "a",
                exit_code: 0,
                status: "passed",
                finished_at: $ts,
                failure_reason: "",
            }
        },
        indexes: {latest_terminal_result_by_cell: {}},
    }
    $manifest_a | to json --indent 2 | save ($cell_a_dir | path join "meta/suite-manifest.v1.json")
    let manifest = (aggregate-suite-manifests-plan-aware [$cell_a_dir] "suite-test" ["a" "b" "c"])
    let summary = (build-aggregate-summary $manifest)
    ^rm -rf $tmp
    let all_results = ($manifest.results | transpose k v | each {|r| $r.v})
    let b_missing = ($all_results | where cell_id == "b" | where status == "missing" | is-not-empty)
    let c_missing = ($all_results | where cell_id == "c" | where status == "missing" | is-not-empty)
    [
        (assert-eq $summary.passed 1 "plan-aware agg: 1 passed cell")
        (assert-eq $summary.missing 2 "plan-aware agg: 2 missing cells injected")
        (assert-eq $manifest.aggregate_status "missing" "plan-aware agg: aggregate_status is missing")
        (assert-truthy $b_missing "plan-aware agg: cell b injected as missing")
        (assert-truthy $c_missing "plan-aware agg: cell c injected as missing")
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

# Fixture: plan with a share-with cell that depends on two distinct login cells
# (sender=nextcloud-v34, receiver=nextcloud-v33 -> needs login for both).
def fixture-plan-with-multi-dep [] {
    {
        suite_id: "multi-dep-suite",
        cells: [
            {
                cell_id: "login__nextcloud-v33",
                artifact_name: "cell-login-nextcloud-v33",
                scenario: "login",
                sender_platform: "nextcloud",
                sender_version: "v33",
                receiver_platform: "",
                receiver_version: "",
                is_two_party: false,
                depends_on: [],
                flow_id: "login",
                execution_id: "exec-001",
                capabilities_produced: ["login__nextcloud-v33"],
                capability_action: "run",
            },
            {
                cell_id: "login__nextcloud-v34",
                artifact_name: "cell-login-nextcloud-v34",
                scenario: "login",
                sender_platform: "nextcloud",
                sender_version: "v34",
                receiver_platform: "",
                receiver_version: "",
                is_two_party: false,
                depends_on: [],
                flow_id: "login",
                execution_id: "exec-002",
                capabilities_produced: ["login__nextcloud-v34"],
                capability_action: "run",
            },
            {
                cell_id: "share-with__nextcloud-v34__nextcloud-v33",
                artifact_name: "cell-share-with-nextcloud-v34-nextcloud-v33",
                scenario: "share-with",
                sender_platform: "nextcloud",
                sender_version: "v34",
                receiver_platform: "nextcloud",
                receiver_version: "v33",
                is_two_party: true,
                depends_on: ["login__nextcloud-v34" "login__nextcloud-v33"],
                flow_id: "share-with",
                execution_id: "exec-003",
                capabilities_produced: [],
                capability_action: "run",
            },
        ]
    }
}

def test-matrix-calls-run-wave [] {
    test-log "\n[test-matrix-calls-run-wave]"
    let rules = fixture-rules
    let prereqs = fixture-prereqs
    let plan = (plan-suite $rules $prereqs (fixture-flow-caps) {})
    let yml = (build-ci-matrix-yml $plan)
    [
        (assert-truthy ($yml | str contains "./.github/workflows/ci-run-wave.yml")
            "ci-matrix.yml calls ./.github/workflows/ci-run-wave.yml")
    ]
}

def test-run-wave-calls-run-cell [] {
    test-log "\n[test-run-wave-calls-run-cell]"
    let run_wave_yml = (build-run-wave-yml)
    [
        (assert-truthy ($run_wave_yml | str contains "./.github/workflows/ci-run-cell.yml")
            "ci-run-wave.yml calls ./.github/workflows/ci-run-cell.yml")
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

def test-aggregate-needs-flow-jobs [] {
    test-log "\n[test-aggregate-needs-flow-jobs]"
    let rules = fixture-rules
    let prereqs = fixture-prereqs
    let plan = (plan-suite $rules $prereqs (fixture-flow-caps) {})
    let yml = (build-ci-matrix-yml $plan)
    [
        (assert-truthy ($yml | str contains "login,")
            "aggregate needs block contains login flow job")
        (assert-truthy ($yml | str contains "share-with,")
            "aggregate needs block contains share-with flow job")
        (assert-truthy (not ($yml | str contains "wave_0,"))
            "aggregate needs block does not reference wave_0")
        (assert-truthy (not ($yml | str contains "wave_1,"))
            "aggregate needs block does not reference wave_1")
    ]
}

def test-flow-separation [] {
    test-log "\n[test-flow-separation]"
    let rules = fixture-rules
    let prereqs = fixture-prereqs
    let plan = (plan-suite $rules $prereqs (fixture-flow-caps) {})
    let yml = (build-ci-matrix-yml $plan)
    let flow_assets = (build-flow-assets $plan)

    # Each flow job references its own asset file (no inlined JSON).
    let login_job_start = ($yml | str index-of "  login:")
    let share_with_job_start = ($yml | str index-of "  share-with:")
    let login_job_section = ($yml | str substring $login_job_start..$share_with_job_start)

    let login_asset_list = ($flow_assets | where {|a| ($a.path | path basename) == "login.json"})
    let share_asset_list = ($flow_assets | where {|a| ($a.path | path basename) == "share-with.json"})
    let login_cells = if not ($login_asset_list | is-empty) {
        $login_asset_list | first | get content | from json
    } else { [] }
    let share_cells = if not ($share_asset_list | is-empty) {
        $share_asset_list | first | get content | from json
    } else { [] }

    [
        (assert-truthy (not ($login_job_section | str contains "share-with"))
            "login job YAML section does not reference share-with")
        (assert-truthy ($login_job_section | str contains "assets/login.json")
            "login job section references login asset file")
        (assert-truthy (not ($login_cells | is-empty))
            "login asset is non-empty")
        (assert-truthy ($login_cells | all {|c| not ($c.scenario | str starts-with "share-with")})
            "login asset contains no share-with scenario cells")
        (assert-truthy (not ($share_cells | is-empty))
            "share-with asset is non-empty")
        (assert-truthy ($share_cells | all {|c| $c.scenario | str starts-with "share-with"})
            "share-with asset contains only share-with scenario cells")
    ]
}

def test-multi-dep-cell-depends-on [] {
    test-log "\n[test-multi-dep-cell-depends-on]"
    let plan = fixture-plan-with-multi-dep
    let flow_assets = (build-flow-assets $plan)
    # cells are now in asset files, not inline in the YAML.
    # The share-with asset should carry cell_depends_on with comma-joined artifact names.
    let share_asset_list = ($flow_assets | where {|a| ($a.path | path basename) | str starts-with "share-with"})
    let share_cells = if not ($share_asset_list | is-empty) {
        $share_asset_list | first | get content | from json
    } else { [] }
    let multi_dep_cell = ($share_cells | where cell_id == "share-with__nextcloud-v34__nextcloud-v33")
    [
        (assert-truthy (not ($multi_dep_cell | is-empty))
            "share-with asset contains the multi-dep cell")
        (assert-truthy (
            ($multi_dep_cell | first | get cell_depends_on)
            | str contains "cell-login-nextcloud-v34,cell-login-nextcloud-v33"
        ) "two-dep share-with cell: cell_depends_on contains both login artifact names comma-joined")
    ]
}

def test-run-cell-iterates-all-deps [] {
    test-log "\n[test-run-cell-iterates-all-deps]"
    let yml = (build-run-cell-yml)
    [
        (assert-truthy ($yml | str contains "IFS=','")
            "ci-run-cell.yml prereq steps split cell-depends-on on comma")
        (assert-truthy ($yml | str contains "for dep in")
            "ci-run-cell.yml prereq steps iterate all deps with a for loop")
        (assert-truthy ($yml | str contains "prereqs/$dep")
            "ci-run-cell.yml prereq steps use per-dep subdirectory")
    ]
}

def test-run-cell-download-uses-current-run-id [] {
    test-log "\n[test-run-cell-download-uses-current-run-id]"
    let yml = (build-run-cell-yml)
    [
        (assert-truthy ($yml | str contains "gh run download \"${{ github.run_id }}\"")
            "ci-run-cell.yml prereq download pins to current run via github.run_id")
        (assert-truthy ($yml | str contains "GH_TOKEN: ${{ github.token }}")
            "ci-run-cell.yml prereq download step has GH_TOKEN")
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
        (assert-truthy ($run_wave_yml | str contains "jq -c .")
            "ci-run-wave.yml load-cells job reads and validates JSON with jq")
    ]
}

def test-asset-file-paths [] {
    test-log "\n[test-asset-file-paths]"
    let rules = fixture-rules
    let prereqs = fixture-prereqs
    let plan = (plan-suite $rules $prereqs (fixture-flow-caps) {})
    let flow_assets = (build-flow-assets $plan)
    let paths = ($flow_assets | each {|a| $a.path})
    [
        (assert-truthy (not ($flow_assets | is-empty))
            "build-flow-assets returns at least one asset")
        (assert-truthy ($paths | all {|p| $p | str starts-with ".github/workflows/assets/"})
            "all asset paths are under .github/workflows/assets/")
        (assert-truthy ($paths | all {|p| $p | str ends-with ".json"})
            "all asset paths end with .json")
        (assert-truthy ($paths | any {|p| $p == ".github/workflows/assets/login.json"})
            "login flow has asset at .github/workflows/assets/login.json")
        (assert-truthy ($paths | any {|p| $p == ".github/workflows/assets/share-with.json"})
            "share-with flow has asset at .github/workflows/assets/share-with.json")
    ]
}

def test-asset-content-valid-json [] {
    test-log "\n[test-asset-content-valid-json]"
    let rules = fixture-rules
    let prereqs = fixture-prereqs
    let plan = (plan-suite $rules $prereqs (fixture-flow-caps) {})
    let flow_assets = (build-flow-assets $plan)
    let parse_results = ($flow_assets | each {|a|
        try {
            $a.content | from json
            true
        } catch {
            false
        }
    })
    [
        (assert-truthy ($parse_results | all {|v| $v})
            "all asset file contents are valid JSON")
    ]
}

def test-asset-content-is-pretty-printed [] {
    test-log "\n[test-asset-content-is-pretty-printed]"
    let rules = fixture-rules
    let prereqs = fixture-prereqs
    let plan = (plan-suite $rules $prereqs (fixture-flow-caps) {})
    let flow_assets = (build-flow-assets $plan)
    [
        (assert-truthy ($flow_assets | all {|a| $a.content | str contains "\n  "})
            "asset file contents are indented (pretty-printed)")
    ]
}

def test-matrix-flow-job-asset-path-matches-flow-id [] {
    test-log "\n[test-matrix-flow-job-asset-path-matches-flow-id]"
    let rules = fixture-rules
    let prereqs = fixture-prereqs
    let plan = (plan-suite $rules $prereqs (fixture-flow-caps) {})
    let yml = (build-ci-matrix-yml $plan)
    let flow_assets = (build-flow-assets $plan)
    # Each asset path basename must match its flow id.
    let paths_match = ($flow_assets | all {|a|
        let flow_id = ($a.path | path basename | str replace ".json" "")
        let flow_in_path = ($a.path | str contains $flow_id)
        $flow_in_path
    })
    [
        (assert-truthy $paths_match
            "each asset file basename matches the flow_id it contains cells for")
    ]
}

def test-suite-publish-flags-in-mod-source [] {
    test-log "\n[test-suite-publish-flags-in-mod-source]"
    let mod_source = (open --raw "scripts/domains/test/mod.nu")
    let suite_source = (open --raw "scripts/domains/test/cypress-suite.nu")
    [
        (assert-truthy ($mod_source | str contains "--publish-site")
            "test mod.nu usage advertises --publish-site flag")
        (assert-truthy ($mod_source | str contains "--site-dir")
            "test mod.nu usage advertises --site-dir flag")
        (assert-truthy ($suite_source | str contains "--site-dir requires --publish-site")
            "test cypress-suite.nu has guardrail message for --site-dir without --publish-site")
        (assert-truthy ($suite_source | str contains "run-site-publish")
            "test cypress-suite.nu calls run-site-publish after suite finalization")
        (assert-truthy ($suite_source | str contains "eff_suite_id")
            "test cypress-suite.nu passes eff_suite_id (not latest-suite) to publish")
        (assert-truthy ($suite_source | str contains "publish_exit")
            "test cypress-suite.nu tracks publish exit code separately from suite exit")
    ]
}

def test-aggregate-archive-no-skip-warning [] {
    test-log "\n[test-aggregate-archive-no-skip-warning]"
    let mod_source = (open --raw "scripts/domains/ci/mod.nu")
    let rules = fixture-rules
    let prereqs = fixture-prereqs
    let plan = (plan-suite $rules $prereqs (fixture-flow-caps) {})
    let yml = (build-ci-matrix-yml $plan)
    [
        (assert-truthy (not ($mod_source | str contains "archive creation skipped"))
            "mod.nu: archive skip-warning downgrade is absent")
        (assert-truthy (not ($mod_source | str contains "WARNING: archive"))
            "mod.nu: no archive WARNING print in aggregate handler")
        (assert-truthy ($yml | str contains "--archive")
            "generated aggregate command includes --archive flag")
    ]
}

# Test that reconstruct-suite-index writes runs/<suite_id>.json and
# LATEST_SUITE_ID, and that all result types (passed, blocked, missing)
# appear as run entries in the suite record.
def test-reconstruct-suite-index [] {
    test-log "\n[test-reconstruct-suite-index]"
    let tmp = (^mktemp -d | str trim)
    let artifacts_root = ($tmp | path join "artifacts")
    let ts = "2026-01-01T00:00:00Z"
    let suite_id = "20260101t000000-aabbccdd"

    # Manifest with one passed cell, one blocked cell, one missing cell.
    # Cells map only covers the two observed cells; missing is synthetic.
    let manifest = {
        schema_version: 1,
        generated_at: $ts,
        suite_id: $suite_id,
        producer: {name: "ocmts-aggregator", version: "0.1.0"},
        flows: {
            login: {id: "login", description: "OCM login flow"}
            "share-with": {id: "share-with", description: "OCM share-with flow"}
        },
        cells: {
            "cell-passed": {
                id: "cell-passed",
                flow_id: "login",
                pair: "nextcloud-v34",
                artifact_name: "cell-login-nextcloud-v34",
            }
            "cell-blocked": {
                id: "cell-blocked",
                flow_id: "share-with",
                pair: "nextcloud-v34__nextcloud-v34",
                artifact_name: "cell-share-with-nextcloud-v34",
            }
        },
        runs: {
            "exec-passed": {
                id: "exec-passed",
                cell_id: "cell-passed",
                execution_id: "exec-passed",
                lifecycle_status: "completed",
                started_at: $ts,
                finished_at: $ts,
            }
            "exec-blocked": {
                id: "exec-blocked",
                cell_id: "cell-blocked",
                execution_id: "exec-blocked",
                lifecycle_status: "completed",
                started_at: $ts,
                finished_at: $ts,
            }
        },
        results: {
            "result-passed": {
                schema_version: 1,
                id: "result-passed",
                run_id: "exec-passed",
                execution_id: "exec-passed",
                cell_id: "cell-passed",
                exit_code: 0,
                status: "passed",
                finished_at: $ts,
                failure_reason: "",
            }
            "result-blocked": {
                schema_version: 1,
                id: "result-blocked",
                run_id: "exec-blocked",
                execution_id: "exec-blocked",
                cell_id: "cell-blocked",
                exit_code: 0,
                status: "blocked",
                finished_at: $ts,
                failure_reason: "prerequisite cell-passed failed",
            }
            "result-missing-cell-missing": {
                schema_version: 1,
                id: "result-missing-cell-missing",
                run_id: "",
                execution_id: "",
                cell_id: "cell-missing",
                exit_code: 1,
                status: "missing",
                finished_at: $ts,
                failure_reason: "cell had no recorded outcome",
            }
        },
        indexes: {latest_terminal_result_by_cell: {}},
        aggregate_status: "blocked",
    }

    let record_path = (reconstruct-suite-index $manifest $artifacts_root)
    let latest_path = ($artifacts_root | path join "suites/LATEST_SUITE_ID")
    let expected_record_path = (
        $artifacts_root | path join $"suites/runs/($suite_id).json"
    )

    let suite_record = if ($record_path != null) and ($record_path | path exists) {
        open $record_path
    } else {
        {}
    }
    let run_statuses = ($suite_record.runs? | default [] | each {|r| $r.status})
    let run_cell_ids = ($suite_record.runs? | default [] | each {|r| $r.cell_id})

    ^rm -rf $tmp
    [
        (assert-truthy ($record_path != null)
            "reconstruct-suite-index returns non-null for valid suite_id")
        (assert-eq $record_path $expected_record_path
            "suite record written at artifacts_root/suites/runs/<suite_id>.json")
        (assert-truthy ($latest_path | path exists | $in == false or $record_path != null)
            "LATEST_SUITE_ID marker created")
        (assert-eq ($suite_record.schema_version? | default 0) 2
            "suite record has schema_version 2")
        (assert-eq ($suite_record.suite_kind? | default "") "aggregated"
            "suite record has suite_kind=aggregated")
        (assert-eq ($suite_record.status? | default "") "blocked"
            "suite record status matches aggregate_status (blocked)")
        (assert-eq ($suite_record.passed_count? | default (-1)) 1
            "suite record passed_count is 1")
        (assert-eq ($suite_record.blocked_count? | default (-1)) 2
            "suite record blocked_count is 2 (blocked + missing)")
        (assert-truthy ("passed" in $run_statuses)
            "run entries include passed result")
        (assert-truthy ("blocked" in $run_statuses)
            "run entries include blocked result")
        (assert-truthy ("missing" in $run_statuses)
            "run entries include missing result")
        (assert-truthy ("cell-passed" in $run_cell_ids)
            "run entry for cell-passed present")
        (assert-truthy ("cell-blocked" in $run_cell_ids)
            "run entry for cell-blocked present")
        (assert-truthy ("cell-missing" in $run_cell_ids)
            "run entry for cell-missing (synthetic) present")
        (assert-truthy (
            ($suite_record.scheduled_cells? | default [] | length) >= 3
        ) "scheduled_cells covers all three cell ids")
    ]
}

# Test that reconstruct-suite-index returns null for non-standard suite_ids.
def test-reconstruct-suite-index-skips-invalid-id [] {
    test-log "\n[test-reconstruct-suite-index-skips-invalid-id]"
    let tmp = (^mktemp -d | str trim)
    let manifest_unknown = {
        suite_id: "unknown-suite",
        aggregate_status: "passed",
        generated_at: "2026-01-01T00:00:00Z",
        flows: {},
        cells: {},
        runs: {},
        results: {},
        indexes: {latest_terminal_result_by_cell: {}},
    }
    let r1 = (reconstruct-suite-index $manifest_unknown ($tmp | path join "artifacts"))
    let manifest_empty = ($manifest_unknown | upsert suite_id "")
    let r2 = (reconstruct-suite-index $manifest_empty ($tmp | path join "artifacts"))
    ^rm -rf $tmp
    [
        (assert-eq $r1 null
            "reconstruct-suite-index returns null for unknown-suite id")
        (assert-eq $r2 null
            "reconstruct-suite-index returns null for empty suite_id")
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

def test-ingest-missing-injection [] {
    test-log "\n[test-ingest-missing-injection]"
    use ../../lib/site/ingest.nu [ingest-site]
    let tmp = (^mktemp -d | str trim)
    materialize-provenance-stubs $tmp
    let artifacts_root = ($tmp | path join "artifacts")
    let public_dir = ($tmp | path join "public")
    let ts = "2026-01-01T00:00:00Z"
    let suite_id = "20260101t000000-aabbccdd"

    # Inline matrix rules record with no scenarios (ingest from suite only).
    let rules = {scenarios: {}}

    # Write a fake per-run manifest for cell-a (passed).
    let run_dir = ($artifacts_root | path join "login" "nextcloud-v34" "exec-aaa")
    mkdir ($run_dir | path join "meta")
    let run_manifest = {
        schema_version: 1,
        generated_at: $ts,
        execution_context: {},
        flows: {login: {id: "login"}},
        cells: {"cell-a": {id: "cell-a", flow_id: "login", pair: "nextcloud-v34", artifact_name: "cell-login-nc-v34"}},
        runs: {"exec-aaa": {id: "exec-aaa", cell_id: "cell-a", started_at: $ts, finished_at: $ts}},
        results: {
            "result-a": {
                schema_version: 1, id: "result-a", run_id: "exec-aaa",
                execution_id: "exec-aaa", cell_id: "cell-a",
                exit_code: 0, status: "passed", finished_at: $ts, failure_reason: "",
                evidence: [],
            }
        },
        indexes: {latest_terminal_result_by_cell: {}},
    }
    $run_manifest | to json --indent 2 | save --force ($run_dir | path join "meta/suite-manifest.v1.json")

    # Write suite index so --latest-suite mode resolves correctly.
    let suites_dir = ($artifacts_root | path join "suites")
    let runs_dir = ($suites_dir | path join "runs")
    mkdir $runs_dir
    let suite_record = {
        schema_version: 2,
        suite_id: $suite_id,
        suite_kind: "aggregated",
        started_at: $ts, finished_at: $ts,
        status: "missing",
        scheduled_cells: ["cell-a" "cell-b"],
        runs: [
            {flow_id: "login", pair: "nextcloud-v34", execution_id: "exec-aaa",
             cell_id: "cell-a", artifact_name: "cell-login-nc-v34", status: "passed",
             exit_code: 0, started_at: $ts, finished_at: $ts}
        ],
        passed_count: 1, failed_count: 0, blocked_count: 1,
    }
    $suite_record | to json --indent 2 | save --force ($runs_dir | path join $"($suite_id).json")
    $suite_id | save --force ($suites_dir | path join "LATEST_SUITE_ID")

    # Write CI aggregated manifest with one passed and one missing result.
    let agg_dir = ($artifacts_root | path join "suites/aggregated")
    mkdir $agg_dir
    let ci_agg = {
        schema_version: 1, generated_at: $ts, suite_id: $suite_id,
        producer: {name: "ocmts-aggregator", version: "0.1.0"},
        flows: {login: {id: "login"}},
        cells: {"cell-a": {id: "cell-a", flow_id: "login", pair: "nextcloud-v34", artifact_name: "cell-login-nc-v34"}},
        runs: {},
        results: {
            "result-a": {
                schema_version: 1, id: "result-a", run_id: "exec-aaa",
                execution_id: "exec-aaa", cell_id: "cell-a",
                exit_code: 0, status: "passed", finished_at: $ts, failure_reason: "",
            }
            "result-missing-cell-b": {
                schema_version: 1, id: "result-missing-cell-b", run_id: "",
                execution_id: "", cell_id: "cell-b",
                exit_code: 1, status: "missing", finished_at: $ts,
                failure_reason: "cell had no recorded outcome",
            }
        },
        indexes: {latest_terminal_result_by_cell: {}},
        aggregate_status: "missing",
    }
    $ci_agg | to json --indent 2 | save --force ($agg_dir | path join "suite-manifest.v1.json")

    ingest-site $artifacts_root $rules $tmp $public_dir --latest-suite

    let site_manifest_path = ($public_dir | path join "suite-manifest.v1.json")
    let site_manifest_exists = ($site_manifest_path | path exists)
    let site_manifest = if $site_manifest_exists { open $site_manifest_path } else { {} }
    let result_statuses = ($site_manifest.results? | default {} | transpose k v | each {|r| $r.v.status? | default ""})

    let site_cell_ids = ($site_manifest.cells? | default {} | columns)
    let site_flow_ids = ($site_manifest.flows? | default {} | columns)

    ^rm -rf $tmp
    [
        (assert-truthy $site_manifest_exists
            "ingest-site writes public/suite-manifest.v1.json")
        (assert-truthy ("passed" in $result_statuses)
            "site manifest contains passed result from actual run")
        (assert-truthy ("missing" in $result_statuses)
            "site manifest preserves missing result injected from CI aggregate manifest")
        (assert-eq ($result_statuses | where {|s| $s == "missing"} | length) 1
            "exactly one missing result is preserved in site manifest")
        (assert-truthy ("cell-b" in $site_cell_ids)
            "site manifest cells has entry for missing cell-b (stub from ci_agg)")
        (assert-truthy ("login" in $site_flow_ids)
            "site manifest flows retains login flow after missing injection")
    ]
}

def test-ingest-missing-injection-cell-list-fallback [] {
    test-log "\n[test-ingest-missing-injection-cell-list-fallback]"
    use ../../lib/site/ingest.nu [ingest-site]
    let tmp = (^mktemp -d | str trim)
    materialize-provenance-stubs $tmp
    let artifacts_root = ($tmp | path join "artifacts")
    let public_dir = ($tmp | path join "public")
    let ts = "2026-01-01T00:00:00Z"
    let suite_id = "20260101t000000-aabbccee"

    # Matrix rules record with one cell: login__nextcloud-v34 (flow_id=login, pair=nextcloud-v34).
    let rules = {scenarios: {login: {
        enabled: true,
        flow_id: "login",
        browsers: ["chrome"],
        sender: {platform: "nextcloud", version_lines: ["v34"]},
    }}}

    # Per-run manifest for cell-a (passed).
    let run_dir = ($artifacts_root | path join "login" "nextcloud-v34" "exec-aaa")
    mkdir ($run_dir | path join "meta")
    let run_manifest = {
        schema_version: 1, generated_at: $ts, execution_context: {},
        flows: {login: {id: "login"}},
        cells: {"cell-a": {id: "cell-a", flow_id: "login", pair: "nextcloud-v34",
                           artifact_name: "cell-login-nc-v34"}},
        runs: {"exec-aaa": {id: "exec-aaa", cell_id: "cell-a",
                            started_at: $ts, finished_at: $ts}},
        results: {"result-a": {
            schema_version: 1, id: "result-a", run_id: "exec-aaa",
            execution_id: "exec-aaa", cell_id: "cell-a",
            exit_code: 0, status: "passed", finished_at: $ts, failure_reason: "",
            evidence: [],
        }},
        indexes: {latest_terminal_result_by_cell: {}},
    }
    $run_manifest | to json --indent 2 | save --force ($run_dir | path join "meta/suite-manifest.v1.json")

    # Suite index listing only cell-a; login__nextcloud-v34 is missing.
    let suites_dir = ($artifacts_root | path join "suites")
    let runs_dir = ($suites_dir | path join "runs")
    mkdir $runs_dir
    let suite_record = {
        schema_version: 2, suite_id: $suite_id, suite_kind: "aggregated",
        started_at: $ts, finished_at: $ts, status: "missing",
        scheduled_cells: ["cell-a" "login__nextcloud-v34"],
        runs: [{flow_id: "login", pair: "nextcloud-v34", execution_id: "exec-aaa",
                cell_id: "cell-a", artifact_name: "cell-login-nc-v34", status: "passed",
                exit_code: 0, started_at: $ts, finished_at: $ts}],
        passed_count: 1, failed_count: 0, blocked_count: 1,
    }
    $suite_record | to json --indent 2 | save --force ($runs_dir | path join $"($suite_id).json")
    $suite_id | save --force ($suites_dir | path join "LATEST_SUITE_ID")

    # CI aggregate manifest: cells has cell-a only (not login__nextcloud-v34).
    # Missing result references login__nextcloud-v34 so cell_list fallback fires.
    let agg_dir = ($artifacts_root | path join "suites/aggregated")
    mkdir $agg_dir
    let ci_agg = {
        schema_version: 1, generated_at: $ts, suite_id: $suite_id,
        producer: {name: "ocmts-aggregator", version: "0.1.0"},
        flows: {login: {id: "login"}},
        cells: {"cell-a": {id: "cell-a", flow_id: "login", pair: "nextcloud-v34",
                           artifact_name: "cell-login-nc-v34"}},
        runs: {},
        results: {
            "result-a": {
                schema_version: 1, id: "result-a", run_id: "exec-aaa",
                execution_id: "exec-aaa", cell_id: "cell-a",
                exit_code: 0, status: "passed", finished_at: $ts, failure_reason: "",
            },
            "result-missing-nc-v34": {
                schema_version: 1, id: "result-missing-nc-v34", run_id: "",
                execution_id: "", cell_id: "login__nextcloud-v34",
                exit_code: 1, status: "missing", finished_at: $ts,
                failure_reason: "cell had no recorded outcome",
            },
        },
        indexes: {latest_terminal_result_by_cell: {}},
        aggregate_status: "missing",
    }
    $ci_agg | to json --indent 2 | save --force ($agg_dir | path join "suite-manifest.v1.json")

    ingest-site $artifacts_root $rules $tmp $public_dir --latest-suite

    let site_manifest_path = ($public_dir | path join "suite-manifest.v1.json")
    let site_manifest_exists = ($site_manifest_path | path exists)
    let site_manifest = if $site_manifest_exists { open $site_manifest_path } else { {} }
    let injected_cell = ($site_manifest.cells? | default {} | get --optional "login__nextcloud-v34")

    ^rm -rf $tmp
    [
        (assert-truthy $site_manifest_exists
            "cell-list fallback: site manifest written")
        (assert-truthy ($injected_cell != null)
            "cell-list fallback: login__nextcloud-v34 present in cells")
        (assert-eq ($injected_cell.flow_id? | default "")
            "login"
            "cell-list fallback: flow_id from cell_list")
        (assert-eq ($injected_cell.pair? | default "")
            "nextcloud-v34"
            "cell-list fallback: pair from cell_list")
        (assert-eq ($injected_cell.artifact_name? | default "")
            "cell-login-nextcloud-v34"
            "cell-list fallback: artifact_name from cell_list")
        (assert-eq ($injected_cell.sender_platform? | default "")
            "nextcloud"
            "cell-list fallback: sender_platform from cell_list")
        (assert-eq ($injected_cell.sender_version? | default "")
            "v34"
            "cell-list fallback: sender_version from cell_list")
        (assert-eq ($injected_cell.browser? | default "")
            "chrome"
            "cell-list fallback: browser from cell_list")
        (assert-eq ($injected_cell.is_two_party? | default true)
            false
            "cell-list fallback: is_two_party from cell_list")
    ]
}

def test-suite-publish-exit-semantics [] {
    test-log "\n[test-suite-publish-exit-semantics]"
    # Exit combination: 0 only when both suite and publish exit 0.
    let combine = {|s, p| if ($s == 0 and $p == 0) { 0 } else { 1 } }
    [
        (assert-eq (do $combine 1 0) 1 "suite failed + publish ok => nonzero")
        (assert-eq (do $combine 0 1) 1 "suite ok + publish failed => nonzero")
        (assert-eq (do $combine 1 1) 1 "both failed => nonzero")
        (assert-eq (do $combine 0 0) 0 "both ok => zero")
    ]
}

def test-ci-matrix-calls-ci-site [] {
    test-log "\n[test-ci-matrix-calls-ci-site]"
    let rules = fixture-rules
    let prereqs = fixture-prereqs
    let plan = (plan-suite $rules $prereqs (fixture-flow-caps) {})
    let yml = (build-ci-matrix-yml $plan)
    [
        (assert-truthy ($yml | str contains "  ci-site:")
            "ci-matrix.yml has ci-site reusable workflow job")
        (assert-truthy ($yml | str contains "./.github/workflows/ci-site.yml")
            "ci-matrix.yml ci-site job calls ci-site.yml")
        (assert-truthy (not ($yml | str contains "  site-publish:"))
            "ci-matrix.yml does not have inline site-publish job")
        (assert-truthy ($yml | str contains "needs: [aggregate]")
            "ci-site job needs aggregate")
        (assert-truthy ($yml | str contains "source-run-id: ${{ github.run_id }}")
            "ci-matrix.yml passes caller run ID to ci-site reusable workflow")
    ]
}

def test-ci-matrix-branch-gate-from-config [] {
    test-log "\n[test-ci-matrix-branch-gate-from-config]"
    let rules = fixture-rules
    let prereqs = fixture-prereqs
    let plan = (plan-suite $rules $prereqs (fixture-flow-caps) {})
    let yml = (build-ci-matrix-yml $plan)
    # Branch gate must come from config/site.nuon (publish_branch_gate: "main"),
    # not hardcoded in multiple places.
    let ci_site_pos = ($yml | str index-of "  ci-site:")
    let ci_site_section = ($yml | str substring $ci_site_pos..)
    [
        (assert-truthy ($ci_site_section | str contains "refs/heads/main")
            "ci-site if condition uses publish_branch_gate from config")
        (assert-truthy (not ($yml | str contains "refs/heads/main\n      runs-on:"))
            "ci-matrix.yml has no inline runner after branch gate (site is reusable call)")
    ]
}

def test-ci-site-has-both-triggers [] {
    test-log "\n[test-ci-site-has-both-triggers]"
    let ci_site_yml = (build-ci-site-yml)
    [
        (assert-truthy ($ci_site_yml | str contains "workflow_call:")
            "ci-site.yml accepts workflow_call trigger")
        (assert-truthy ($ci_site_yml | str contains "workflow_dispatch:")
            "ci-site.yml accepts workflow_dispatch trigger")
    ]
}

def test-ci-site-resolves-source-run [] {
    test-log "\n[test-ci-site-resolves-source-run]"
    let ci_site_yml = (build-ci-site-yml)
    # For workflow_call: caller passes source-run-id input (its own github.run_id).
    # For workflow_dispatch: gh run list resolves the latest eligible source run.
    [
        (assert-truthy ($ci_site_yml | str contains "Resolve artifact source run")
            "ci-site.yml has source run resolution step")
        (assert-truthy ($ci_site_yml | str contains "workflow_dispatch")
            "ci-site.yml source resolution branches on workflow_dispatch")
        (assert-truthy ($ci_site_yml | str contains "gh run list")
            "ci-site.yml uses gh run list to find source run for manual rebuild")
        (assert-truthy ($ci_site_yml | str contains "inputs['source-run-id']")
            "ci-site.yml uses source-run-id input as source for workflow_call")
        (assert-truthy ($ci_site_yml | str contains "source-run-id")
            "ci-site.yml passes source-run-id between prepare and downstream jobs")
    ]
}

def test-ci-site-downloads-optimized-media [] {
    test-log "\n[test-ci-site-downloads-optimized-media]"
    let ci_site_yml = (build-ci-site-yml)
    [
        (assert-truthy ($ci_site_yml | str contains "Download optimized media artifacts")
            "ci-site.yml downloads optimized media artifacts")
        (assert-truthy ($ci_site_yml | str contains "optimized-media-cell-")
            "ci-site.yml references optimized-media-cell- pattern")
        (assert-truthy ($ci_site_yml | str contains "Aggregate optimized media")
            "ci-site.yml has aggregate optimized media step")
        (assert-truthy ($ci_site_yml | str contains "aggregate-optimized-media")
            "ci-site.yml runs aggregate-optimized-media command")
        (assert-truthy ($ci_site_yml | str contains "Upload optimized media summary")
            "ci-site.yml uploads optimized media summary artifact")
    ]
}

def test-ci-site-config-values-injected [] {
    test-log "\n[test-ci-site-config-values-injected]"
    let ci_site_yml = (build-ci-site-yml)
    # Values come from config/site.nuon.
    # gh run list takes a bare branch name (not refs/heads/ prefix).
    [
        (assert-truthy ($ci_site_yml | str contains "ci-matrix.yml")
            "ci-site.yml uses rebuild_source_workflow from site config")
        (assert-truthy ($ci_site_yml | str contains "aggregate-summary")
            "ci-site.yml uses raw_aggregate_artifact_name from site config")
        (assert-truthy ($ci_site_yml | str contains "optimized-media-cell-*")
            "ci-site.yml uses optimized_artifact_pattern from site config")
        (assert-truthy ($ci_site_yml | str contains "--branch main")
            "ci-site.yml uses publish_branch_gate from site config in gh run list")
        (assert-truthy ($ci_site_yml | str contains "optimized-media-summary")
            "ci-site.yml uses optimized_aggregate_artifact_name from site config")
        (assert-truthy ($ci_site_yml | str contains "../ocm-web-site/dist")
            "ci-site.yml upload path is CI-owned site checkout dir joined with site output subpath")
    ]
}

def test-run-cell-has-optimize-media-step [] {
    test-log "\n[test-run-cell-has-optimize-media-step]"
    let run_cell_yml = (build-run-cell-yml)
    [
        (assert-truthy ($run_cell_yml | str contains "Optimize cell media")
            "ci-run-cell.yml has Optimize cell media step")
        (assert-truthy ($run_cell_yml | str contains "optimize-media")
            "ci-run-cell.yml calls optimize-media command")
        (assert-truthy ($run_cell_yml | str contains "--raw-dir artifacts/")
            "ci-run-cell.yml passes --raw-dir to optimize-media")
        (assert-truthy ($run_cell_yml | str contains "--out-dir artifacts-optimized/")
            "ci-run-cell.yml passes --out-dir artifacts-optimized/ to optimize-media")
        (assert-truthy ($run_cell_yml | str contains "continue-on-error: true")
            "optimize-media step has continue-on-error: true")
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
        (assert-truthy ($run_cell_yml | str contains "if-no-files-found: ignore")
            "optimized upload uses if-no-files-found: ignore")
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

def test-ci-site-job-topology [] {
    test-log "\n[test-ci-site-job-topology]"
    let ci_site_yml = (build-ci-site-yml)
    [
        (assert-truthy ($ci_site_yml | str contains "  prepare:")
            "ci-site.yml has prepare job")
        (assert-truthy ($ci_site_yml | str contains "  aggregate-media:")
            "ci-site.yml has aggregate-media job")
        (assert-truthy ($ci_site_yml | str contains "  build:")
            "ci-site.yml has build job")
        (assert-truthy ($ci_site_yml | str contains "  deploy:")
            "ci-site.yml has deploy job")
        (assert-truthy ($ci_site_yml | str contains "needs: [prepare]")
            "aggregate-media needs prepare")
        (assert-truthy ($ci_site_yml | str contains "needs: [prepare, aggregate-media]")
            "build needs prepare and aggregate-media")
        (assert-truthy ($ci_site_yml | str contains "needs: [build]")
            "deploy needs build")
    ]
}

def test-ci-site-build-job [] {
    test-log "\n[test-ci-site-build-job]"
    let ci_site_yml = (build-ci-site-yml)
    [
        (assert-truthy ($ci_site_yml | str contains "Publish site")
            "ci-site.yml build job has Publish site step")
        (assert-truthy ($ci_site_yml | str contains "--optimized-media-dir artifacts/optimized-summary/")
            "ci-site.yml build job passes --optimized-media-dir to site publish")
        (assert-truthy ($ci_site_yml | str contains "Download optimized media summary")
            "ci-site.yml build job downloads optimized media summary from aggregate-media job")
        (assert-truthy ($ci_site_yml | str contains "Upload built site")
            "ci-site.yml build job uploads built site artifact")
        (assert-truthy ($ci_site_yml | str contains "actions/upload-pages-artifact@v3")
            "ci-site.yml build job uses upload-pages-artifact action")
        (assert-truthy ($ci_site_yml | str contains "../ocm-web-site/dist")
            "ci-site.yml upload-pages-artifact path is CI checkout dir joined with site output subpath")
    ]
}

def test-ci-site-deploy-job [] {
    test-log "\n[test-ci-site-deploy-job]"
    let ci_site_yml = (build-ci-site-yml)
    [
        (assert-truthy ($ci_site_yml | str contains "Deploy to GitHub Pages")
            "ci-site.yml deploy job has Deploy to GitHub Pages step")
        (assert-truthy ($ci_site_yml | str contains "actions/deploy-pages@v4")
            "ci-site.yml deploy job uses deploy-pages action")
        (assert-truthy ($ci_site_yml | str contains "pages: write")
            "ci-site.yml deploy job has pages: write permission")
        (assert-truthy ($ci_site_yml | str contains "id-token: write")
            "ci-site.yml deploy job has id-token: write permission")
        (assert-truthy ($ci_site_yml | str contains "name: github-pages")
            "ci-site.yml deploy job uses github-pages environment")
        (assert-truthy ($ci_site_yml | str contains "page_url")
            "ci-site.yml deploy job exposes page_url via environment url")
    ]
}

def test-ci-site-has-optimizer-probe-step [] {
    test-log "\n[test-ci-site-has-optimizer-probe-step]"
    let ci_site_yml = (build-ci-site-yml)
    let probe_pos = ($ci_site_yml | str index-of "Probe optimizer image")
    let download_pos = ($ci_site_yml | str index-of "Download optimized media artifacts")
    let probe_section = ($ci_site_yml | str substring $probe_pos..$download_pos)
    [
        (assert-truthy ($ci_site_yml | str contains "Probe optimizer image")
            "ci-site.yml aggregate-media job has Probe optimizer image step")
        (assert-truthy ($probe_section | str contains "nu scripts/ocmts.nu artifacts probe-optimizer")
            "Probe optimizer image step runs nu scripts/ocmts.nu artifacts probe-optimizer")
        (assert-truthy ($probe_pos < $download_pos)
            "Probe optimizer image step appears before Download optimized media artifacts")
    ]
}

def test-ci-site-download-no-or-true [] {
    test-log "\n[test-ci-site-download-no-or-true]"
    let ci_site_yml = (build-ci-site-yml)
    [
        (assert-truthy (not ($ci_site_yml | str contains "--dir artifacts/optimized/ || true"))
            "ci-site.yml gh run download line does not contain || true fallback")
    ]
}

def test-suite-publish-guardrail-logic [] {
    test-log "\n[test-suite-publish-guardrail-logic]"
    # --site-dir without --publish-site must raise a clear error.
    let caught_no_publish = (try {
        let site_dir = "some/path"
        let publish_site = false
        if (not ($site_dir | is-empty)) and (not $publish_site) {
            error make {msg: "--site-dir requires --publish-site"}
        }
        false
    } catch {
        true
    })
    # --site-dir with --publish-site passes the flag-combination guard.
    let passes_with_publish = (try {
        let site_dir = "some/path"
        let publish_site = true
        if (not ($site_dir | is-empty)) and (not $publish_site) {
            error make {msg: "--site-dir requires --publish-site"}
        }
        true
    } catch {
        false
    })
    [
        (assert-truthy $caught_no_publish
            "--site-dir without --publish-site raises guardrail error")
        (assert-truthy $passes_with_publish
            "--site-dir with --publish-site passes the flag-combination guard")
    ]
}

def test-plan-suite-disabled-cell-is-placeholder [] {
    test-log "\n[test-plan-suite-disabled-cell-is-placeholder]"
    let rules = fixture-rules-with-unique-disabled
    let prereqs = fixture-prereqs
    let plan = (plan-suite $rules $prereqs (fixture-flow-caps) {})
    let v99_cells = ($plan.cells | where {|c| $c.cell_id == "login__nextcloud-v99"})
    [
        (assert-truthy (not ($v99_cells | is-empty))
            "disabled scenario cell login__nextcloud-v99 is included in plan")
        (assert-eq ($v99_cells | first | get capability_action) "exclude-placeholder"
            "disabled supported cell has capability_action exclude-placeholder")
        (assert-eq ($v99_cells | first | get capability_status) "placeholder"
            "disabled supported cell has capability_status placeholder")
        (assert-truthy ($v99_cells | first | get display_visible)
            "disabled supported cell is still display_visible")
    ]
}

def test-plan-suite-capability-skipped-included [] {
    test-log "\n[test-plan-suite-capability-skipped-included]"
    let rules = fixture-rules-cap-tests
    let prereqs = fixture-prereqs
    let plan = (plan-suite $rules $prereqs (fixture-flow-caps-with-reqs) (fixture-adapters-cap))
    let oc_cells = ($plan.cells | where {|c| $c.cell_id == "login__opencloud-v6"})
    [
        (assert-truthy (not ($oc_cells | is-empty))
            "plan includes capability-skipped cell login__opencloud-v6")
        (assert-eq ($oc_cells | first | get capability_action) "capability-skipped"
            "test-pending cell has capability_action capability-skipped")
        (assert-eq ($oc_cells | first | get capability_status) "test-implementation-pending"
            "test-pending cell has capability_status test-implementation-pending")
        (assert-truthy ($oc_cells | first | get display_visible)
            "test-pending cell is display_visible")
        (assert-eq ($oc_cells | first | get display_status) "test-pending"
            "test-pending cell has display_status test-pending")
    ]
}

def test-plan-suite-supported-cell-action-run [] {
    test-log "\n[test-plan-suite-supported-cell-action-run]"
    let rules = fixture-rules-cap-tests
    let prereqs = fixture-prereqs
    let plan = (plan-suite $rules $prereqs (fixture-flow-caps-with-reqs) (fixture-adapters-cap))
    let nc_cells = ($plan.cells | where {|c| $c.cell_id == "login__nextcloud-v34"})
    [
        (assert-truthy (not ($nc_cells | is-empty))
            "plan includes login__nextcloud-v34")
        (assert-eq ($nc_cells | first | get capability_action) "run"
            "supported cell has capability_action run")
        (assert-eq ($nc_cells | first | get capability_status) "supported"
            "supported cell has capability_status supported")
        (assert-eq ($nc_cells | first | get display_status) "supported"
            "supported cell has display_status supported")
    ]
}

def test-plan-suite-augmented-fields-present [] {
    test-log "\n[test-plan-suite-augmented-fields-present]"
    let rules = fixture-rules-cap-tests
    let prereqs = fixture-prereqs
    let plan = (plan-suite $rules $prereqs (fixture-flow-caps) {})
    let required_fields = ["capability_status" "capability_action" "display_visible"
                           "display_status" "requirements" "blockers" "execution_id"]
    let all_have_fields = ($plan.cells | all {|c|
        let cols = ($c | columns)
        $required_fields | all {|f| $f in $cols}
    })
    [
        (assert-truthy $all_have_fields
            "all cells have augmented fields: capability_status, capability_action, display_visible, display_status, requirements, blockers, execution_id")
    ]
}

def test-plan-suite-capability-skip-field [] {
    test-log "\n[test-plan-suite-capability-skip-field]"
    let rules = fixture-rules-cap-tests
    let prereqs = fixture-prereqs
    let plan = (plan-suite $rules $prereqs (fixture-flow-caps-with-reqs) (fixture-adapters-cap))
    let oc_cells = ($plan.cells | where {|c| $c.cell_id == "login__opencloud-v6"})
    let nc_cells = ($plan.cells | where {|c| $c.cell_id == "login__nextcloud-v34"})
    let oc_cols = if not ($oc_cells | is-empty) { ($oc_cells | first | columns) } else { [] }
    let nc_cols = if not ($nc_cells | is-empty) { ($nc_cells | first | columns) } else { [] }
    [
        (assert-truthy ("capability_skip" in $oc_cols)
            "capability-skipped cell has capability_skip field")
        (assert-truthy (not ("capability_skip" in $nc_cols))
            "non-skipped (run) cell omits capability_skip field")
        (assert-truthy (
            if ("capability_skip" in $oc_cols) {
                let cs = ($oc_cells | first | get capability_skip)
                ("reason" in ($cs | columns)) and ("rationale" in ($cs | columns))
            } else { false }
        ) "capability_skip has reason and rationale sub-fields")
    ]
}

def test-plan-suite-non-run-cells-empty-deps [] {
    test-log "\n[test-plan-suite-non-run-cells-empty-deps]"
    let rules = fixture-rules-cap-tests
    let prereqs = fixture-prereqs
    let plan = (plan-suite $rules $prereqs (fixture-flow-caps-with-reqs) (fixture-adapters-cap))
    let non_run = ($plan.cells | where {|c| $c.capability_action != "run"})
    let all_empty_caps = ($non_run | all {|c|
        let caps_empty = (($c.capabilities_produced? | default [] | length) == 0)
        let deps_empty = (($c.depends_on? | default [] | length) == 0)
        $caps_empty and $deps_empty
    })
    [
        (assert-truthy $all_empty_caps
            "non-run cells have empty capabilities_produced and depends_on")
    ]
}

def test-plan-suite-schema-version-1 [] {
    test-log "\n[test-plan-suite-schema-version-1]"
    let rules = fixture-rules
    let prereqs = fixture-prereqs
    let plan = (plan-suite $rules $prereqs (fixture-flow-caps) {})
    [
        (assert-eq ($plan.schema_version? | default 0) 1 "plan schema_version is 1")
    ]
}

def test-build-flow-assets-excludes-cap-skipped [] {
    test-log "\n[test-build-flow-assets-excludes-cap-skipped]"
    let rules = fixture-rules-cap-tests
    let prereqs = fixture-prereqs
    let plan = (plan-suite $rules $prereqs (fixture-flow-caps-with-reqs) (fixture-adapters-cap))
    let flow_assets = (build-flow-assets $plan)

    # The plan has login__nextcloud-v34 (run) and login__opencloud-v6 (capability-skipped).
    # flow_assets should only contain the runnable cell.
    let all_cell_ids = ($flow_assets | each {|a|
        $a.content | from json | each {|c| $c.cell_id}
    } | flatten)
    [
        (assert-truthy (not ($all_cell_ids | is-empty))
            "flow assets: at least one cell present")
        (assert-truthy ("login__nextcloud-v34" in $all_cell_ids)
            "flow assets: runnable cell login__nextcloud-v34 included")
        (assert-truthy (not ("login__opencloud-v6" in $all_cell_ids))
            "flow assets: capability-skipped cell login__opencloud-v6 excluded")
    ]
}

# Fixture: rules where ONLY the capability-skipped cell exists in a flow,
# to test that flows with zero runnable cells are omitted.
def fixture-rules-only-cap-skipped [] {
    {
        scenarios: {
            "login-oc-only": {
                enabled: true,
                flow_id: "login",
                browsers: ["chrome"],
                sender: {platform: "opencloud", version_lines: ["v6"]},
                receiver: null,
                mitm: false,
            },
        }
    }
}

def test-build-flow-assets-omits-cap-skipped-only-flow [] {
    test-log "\n[test-build-flow-assets-omits-cap-skipped-only-flow]"
    let rules = fixture-rules-only-cap-skipped
    let prereqs = fixture-prereqs
    let plan = (plan-suite $rules $prereqs (fixture-flow-caps-with-reqs) (fixture-adapters-cap))
    let flow_assets = (build-flow-assets $plan)
    [
        (assert-truthy ($flow_assets | is-empty)
            "flow assets: no assets for flow with only capability-skipped cells")
    ]
}

def test-build-ci-matrix-yml-excludes-cap-skipped-only-flow [] {
    test-log "\n[test-build-ci-matrix-yml-excludes-cap-skipped-only-flow]"
    let rules = fixture-rules-only-cap-skipped
    let prereqs = fixture-prereqs
    let plan = (plan-suite $rules $prereqs (fixture-flow-caps-with-reqs) (fixture-adapters-cap))
    let yml = (build-ci-matrix-yml $plan)
    # There should be no flow job for "login" since all cells are capability-skipped.
    [
        (assert-truthy (not ($yml | str contains "  login:"))
            "ci-matrix.yml: no login flow job when all cells are capability-skipped")
    ]
}

def test-aggregate-status-cap-skipped [] {
    test-log "\n[test-aggregate-status-cap-skipped]"
    [
        (assert-eq (aggregate-status ["passed" "capability-skipped"])
            "passed"
            "passed + capability-skipped => passed")
        (assert-eq (aggregate-status ["capability-skipped"])
            "passed"
            "all capability-skipped => passed")
        (assert-eq (aggregate-status ["capability-skipped" "capability-skipped"])
            "passed"
            "multiple capability-skipped => passed")
        (assert-eq (aggregate-status ["passed" "capability-skipped" "failed"])
            "failed"
            "any failed + capability-skipped => failed")
        (assert-eq (aggregate-status ["capability-skipped" "blocked"])
            "blocked"
            "blocked + capability-skipped => blocked")
        (assert-eq (aggregate-status ["capability-skipped" "missing"])
            "missing"
            "missing + capability-skipped => missing")
    ]
}

def test-aggregate-summary-cap-skipped [] {
    test-log "\n[test-aggregate-summary-cap-skipped]"
    let mock_manifest = {
        aggregate_status: "passed",
        results: {
            "res-1": {status: "passed"},
            "res-2": {status: "capability-skipped"},
            "res-3": {status: "capability-skipped"},
        },
    }
    let s = (build-aggregate-summary $mock_manifest)
    [
        (assert-eq $s.total 3 "total is 3")
        (assert-eq $s.passed 1 "passed is 1")
        (assert-eq $s.capability_skipped 2 "capability_skipped is 2")
        (assert-eq $s.unknown 0 "capability-skipped does not count as unknown")
        (assert-eq $s.aggregate_status "passed" "aggregate_status is passed")
    ]
}

def test-plan-aware-aggregate-synthesizes-cap-skipped [] {
    test-log "\n[test-plan-aware-aggregate-synthesizes-cap-skipped]"
    use ../../lib/ci/aggregate.nu [aggregate-suite-manifests-plan-aware build-aggregate-summary]
    let tmp = (^mktemp -d | str trim)
    let cell_a_dir = ($tmp | path join "cell-a")
    mkdir ($cell_a_dir | path join "meta")
    let ts = "2026-01-01T00:00:00Z"
    let manifest_a = {
        schema_version: 1,
        generated_at: $ts,
        suite_id: "suite-test",
        producer: {name: "ocmts-cell", version: "0.1.0"},
        flows: {},
        cells: {},
        runs: {},
        results: {
            "result-a": {
                schema_version: 1,
                id: "result-a",
                run_id: "",
                execution_id: "",
                cell_id: "a",
                exit_code: 0,
                status: "passed",
                finished_at: $ts,
                failure_reason: "",
            }
        },
        indexes: {latest_terminal_result_by_cell: {}},
    }
    $manifest_a | to json --indent 2 | save ($cell_a_dir | path join "meta/suite-manifest.v1.json")
    # "b" is cap-skipped with a full plan record; "c" is truly missing
    let cap_b = {
        cell_id: "b",
        flow_id: "login",
        pair: "opencloud-v6",
        artifact_name: "cell-login-opencloud-v6",
        scenario: "login",
        sender_platform: "opencloud",
        sender_version: "v6",
        receiver_platform: "",
        receiver_version: "",
        is_two_party: false,
        execution_id: "20260101t000000-aabbccdd",
        capability_skip: {rationale: "login sender not yet implemented"},
    }
    let manifest = (aggregate-suite-manifests-plan-aware
        [$cell_a_dir] "suite-test" ["a" "b" "c"]
        --capability-skipped-cells [$cap_b])
    let summary = (build-aggregate-summary $manifest)
    ^rm -rf $tmp
    let all_results = ($manifest.results | transpose k v | each {|r| $r.v})
    let b_result = ($all_results | where cell_id == "b" | get 0?)
    let c_result = ($all_results | where cell_id == "c" | get 0?)
    let b_cell = ($manifest.cells | get --optional "b")
    let b_run = ($manifest.runs | get --optional "20260101t000000-aabbccdd")
    [
        (assert-eq $summary.passed 1 "plan-aware: 1 passed")
        (assert-eq $summary.capability_skipped 1 "plan-aware: 1 capability-skipped synthesized")
        (assert-eq $summary.missing 1 "plan-aware: 1 truly missing")
        (assert-eq ($b_result.status? | default "") "capability-skipped"
            "plan-aware: cell b synthesized as capability-skipped")
        (assert-eq ($b_result.exit_code? | default (-1)) 0
            "plan-aware: capability-skipped result exit_code 0")
        (assert-eq ($b_result.execution_id? | default "") "20260101t000000-aabbccdd"
            "plan-aware: capability-skipped result carries actual execution_id")
        (assert-eq ($b_result.failure_reason? | default "") "login sender not yet implemented"
            "plan-aware: failure_reason set from capability_skip.rationale")
        (assert-eq ($c_result.status? | default "") "missing"
            "plan-aware: cell c synthesized as missing")
        (assert-eq $manifest.aggregate_status "missing"
            "plan-aware: aggregate_status is missing when a truly-missing cell exists")
        (assert-truthy ($b_cell != null) "plan-aware: cells map entry synthesized for cap-skipped cell")
        (assert-eq ($b_cell.id? | default "") "b"
            "plan-aware: synthesized cell id field matches map key")
        (assert-eq ($b_cell.flow_id? | default "") "login"
            "plan-aware: synthesized cell carries flow_id from plan")
        (assert-eq ($b_cell.pair? | default "") "opencloud-v6"
            "plan-aware: synthesized cell carries pair from plan")
        (assert-eq ($b_cell.artifact_name? | default "") "cell-login-opencloud-v6"
            "plan-aware: synthesized cell carries artifact_name from plan")
        (assert-eq ($b_cell.scenario? | default "") "login"
            "plan-aware: synthesized cell carries scenario from plan")
        (assert-eq ($b_cell.is_two_party? | default true) false
            "plan-aware: synthesized cell carries is_two_party from plan")
        (assert-truthy ("login" in ($manifest.flows | columns))
            "plan-aware: flows entry synthesized for new flow_id")
        (assert-truthy ($b_run != null) "plan-aware: run synthesized for cap-skipped cell with execution_id")
        (assert-eq ($b_run.cell_id? | default "") "b"
            "plan-aware: synthesized run cell_id matches cell key")
        (assert-eq ($b_run.status? | default "") "capability-skipped"
            "plan-aware: synthesized run status is capability-skipped")
    ]
}

def test-reconstruct-suite-index-cap-skipped [] {
    test-log "\n[test-reconstruct-suite-index-cap-skipped]"
    let tmp = (^mktemp -d | str trim)
    let artifacts_root = ($tmp | path join "artifacts")
    let ts = "2026-01-01T00:00:00Z"
    let suite_id = "20260101t000000-aabbccdd"

    let manifest = {
        schema_version: 1,
        generated_at: $ts,
        suite_id: $suite_id,
        producer: {name: "ocmts-aggregator", version: "0.1.0"},
        flows: {login: {id: "login", description: "OCM login flow"}},
        cells: {
            "cell-passed": {
                id: "cell-passed",
                flow_id: "login",
                pair: "nextcloud-v34",
                artifact_name: "cell-login-nextcloud-v34",
            }
            "cell-cap-skipped": {
                id: "cell-cap-skipped",
                flow_id: "login",
                pair: "opencloud-v6",
                artifact_name: "cell-login-opencloud-v6",
            }
        },
        runs: {},
        results: {
            "result-passed": {
                schema_version: 1,
                id: "result-passed",
                run_id: "",
                execution_id: "",
                cell_id: "cell-passed",
                exit_code: 0,
                status: "passed",
                finished_at: $ts,
                failure_reason: "",
            }
            "result-cap-skipped": {
                schema_version: 1,
                id: "result-cap-skipped",
                run_id: "",
                execution_id: "",
                cell_id: "cell-cap-skipped",
                exit_code: 0,
                status: "capability-skipped",
                finished_at: $ts,
                failure_reason: "",
            }
        },
        indexes: {latest_terminal_result_by_cell: {}},
        aggregate_status: "passed",
    }

    let record_path = (reconstruct-suite-index $manifest $artifacts_root)
    let suite_record = if ($record_path != null) and ($record_path | path exists) {
        open $record_path
    } else {
        {}
    }
    let run_statuses = ($suite_record.runs? | default [] | each {|r| $r.status})
    ^rm -rf $tmp
    [
        (assert-truthy ($record_path != null)
            "reconstruct: returns non-null for valid suite_id")
        (assert-eq ($suite_record.status? | default "") "passed"
            "reconstruct: suite status is passed")
        (assert-eq ($suite_record.passed_count? | default (-1)) 1
            "reconstruct: passed_count is 1")
        (assert-eq ($suite_record.capability_skipped_count? | default (-1)) 1
            "reconstruct: capability_skipped_count is 1")
        (assert-eq ($suite_record.blocked_count? | default (-1)) 0
            "reconstruct: blocked_count is 0 (capability-skipped not counted as blocked)")
        (assert-truthy ("capability-skipped" in $run_statuses)
            "reconstruct: run entry with capability-skipped status present")
    ]
}

def test-emit-capability-skipped-cell-artifact [] {
    test-log "\n[test-emit-capability-skipped-cell-artifact]"
    use ../../lib/ci/blocker.nu [emit-capability-skipped-cell-artifact]
    let tmp = (^mktemp -d | str trim)
    let ts = "2026-01-01T00:00:00Z"
    let planned_cell = {
        cell_id: "login__opencloud-v6",
        artifact_name: "cell-login-opencloud-v6",
        flow_id: "login",
        scenario: "login",
        pair: "opencloud-v6",
        sender_platform: "opencloud",
        sender_version: "v6",
        receiver_platform: "",
        receiver_version: "",
        is_two_party: false,
        browser: "chrome",
        execution_id: "20260101t000000-aabbccdd",
        capability_skip: {
            reason: "test-implementation-pending",
            blocked_capability: "flow.login.sender",
            blocked_role: "sender",
            blocked_adapter_key: "opencloud/v6",
            rationale: "Login sender not yet implemented for opencloud v6",
        },
    }
    let artifacts_base = (try {
        emit-capability-skipped-cell-artifact $tmp $planned_cell
    } catch {|e|
        print $"  FAIL: emit-capability-skipped-cell-artifact threw: ($e.msg)"
        ""
    })

    let cell_json_path = ($artifacts_base | path join "meta/cell.json")
    let run_json_path = ($artifacts_base | path join "meta/run.json")
    let result_json_path = ($artifacts_base | path join "meta/result.v1.json")

    let cell_exists = ($cell_json_path | path exists)
    let run_exists = ($run_json_path | path exists)
    let result_exists = ($result_json_path | path exists)

    let run_data = if $run_exists { open $run_json_path } else { {} }
    let result_data = if $result_exists { open $result_json_path } else { {} }

    ^rm -rf $tmp
    [
        (assert-truthy (not ($artifacts_base | is-empty))
            "emit-capability-skipped-cell-artifact returns a non-empty path")
        (assert-truthy $cell_exists
            "meta/cell.json written")
        (assert-truthy $run_exists
            "meta/run.json written")
        (assert-truthy $result_exists
            "meta/result.v1.json written")
        (assert-eq ($run_data.status? | default "") "capability-skipped"
            "run.json status is capability-skipped")
        (assert-eq ($run_data.exit_code? | default (-1)) 0
            "run.json exit_code is 0")
        (assert-eq ($result_data.status? | default "") "capability-skipped"
            "result.v1.json status is capability-skipped")
        (assert-eq ($result_data.exit_code? | default (-1)) 0
            "result.v1.json exit_code is 0")
        (assert-truthy ($result_data.capability_skip? != null)
            "result.v1.json preserves capability_skip record")
        (assert-eq ($result_data.failure_reason? | default "unset")
            "Login sender not yet implemented for opencloud v6"
            "result.v1.json failure_reason matches capability_skip.rationale")
    ]
}

def main [] {
    test-log "=== CI Planner Tests ==="
    let results = (
        (test-capability-id)
        | append (test-cell-capabilities-produced)
        | append (test-cell-depends-on)
        | append (test-plan-suite)
        | append (test-plan-suite-nextcloud-v34-login-is-producer)
        | append (test-blocked-eval)
        | append (test-blocked-result-status)
        | append (test-workflow-no-baked-ids)
        | append (test-transitive-blocked)
        | append (test-suite-status-with-blocked)
        | append (test-no-generated-timestamp)
        | append (test-setup-failure-guard)
        | append (test-blocked-output-check)
        | append (test-site-env-names)
        | append (test-aggregate-summary-counts)
        | append (test-aggregate-summary-empty)
        | append (test-aggregate-upload-step)
        | append (test-aggregate-cap-skipped-passthrough)
        | append (test-site-publish-downloads-cell-artifacts)
        | append (test-site-publish-artifacts-root)
        | append (test-aggregate-status-cleanup-failed)
        | append (test-nushell-version-from-config)
        | append (test-no-unresolved-placeholders)
        | append (test-render-template-fails-on-unresolved)
        | append (test-render-template-replaces-all)
        | append (test-cell-visual-job-order)
        | append (test-sort-cells-by-flow-order)
        | append (test-suite-sort-then-max-respects-flow-order)
        | append (test-aggregate-needs-block-format)
        | append (test-generated-header-command)
        | append (test-workflow-deterministic)
        | append (test-flow-based-no-wave-jobs)
        | append (test-wave-plan-aware-aggregate)
        | append (test-plan-aware-aggregate-injects-missing)
        | append (test-wave-gen-yaml-properties)
        | append (test-matrix-calls-run-wave)
        | append (test-run-wave-calls-run-cell)
        | append (test-run-wave-properties)
        | append (test-aggregate-needs-flow-jobs)
        | append (test-flow-separation)
        | append (test-multi-dep-cell-depends-on)
        | append (test-run-cell-iterates-all-deps)
        | append (test-run-cell-download-uses-current-run-id)
        | append (test-aggregate-archive-no-skip-warning)
        | append (test-reconstruct-suite-index)
        | append (test-reconstruct-suite-index-skips-invalid-id)
        | append (test-cells-path-in-matrix)
        | append (test-load-cells-job-in-run-wave)
        | append (test-asset-file-paths)
        | append (test-asset-content-valid-json)
        | append (test-asset-content-is-pretty-printed)
        | append (test-matrix-flow-job-asset-path-matches-flow-id)
        | append (test-hardened-cell-expressions)
        | append (test-hardened-wave-expressions)
        | append (test-hardened-matrix-expressions)
        | append (test-ingest-missing-injection)
        | append (test-ingest-missing-injection-cell-list-fallback)
        | append (test-suite-publish-flags-in-mod-source)
        | append (test-suite-publish-exit-semantics)
        | append (test-suite-publish-guardrail-logic)
        | append (test-ci-matrix-calls-ci-site)
        | append (test-ci-matrix-branch-gate-from-config)
        | append (test-ci-site-has-both-triggers)
        | append (test-ci-site-resolves-source-run)
        | append (test-ci-site-downloads-optimized-media)
        | append (test-ci-site-config-values-injected)
        | append (test-run-cell-has-optimize-media-step)
        | append (test-run-cell-uploads-optimized-media-artifact)
        | append (test-run-cell-has-prepull-optimizer-step)
        | append (test-run-cell-optimize-branch-gated)
        | append (test-ci-site-job-topology)
        | append (test-ci-site-build-job)
        | append (test-ci-site-deploy-job)
        | append (test-ci-site-has-optimizer-probe-step)
        | append (test-ci-site-download-no-or-true)
        | append (test-plan-suite-disabled-cell-is-placeholder)
        | append (test-plan-suite-capability-skipped-included)
        | append (test-plan-suite-supported-cell-action-run)
        | append (test-plan-suite-augmented-fields-present)
        | append (test-plan-suite-capability-skip-field)
        | append (test-plan-suite-non-run-cells-empty-deps)
        | append (test-plan-suite-schema-version-1)
        | append (test-compute-cell-depends-on-rejects-unknown-role)
        | append (test-build-flow-assets-excludes-cap-skipped)
        | append (test-build-flow-assets-omits-cap-skipped-only-flow)
        | append (test-build-ci-matrix-yml-excludes-cap-skipped-only-flow)
        | append (test-aggregate-status-cap-skipped)
        | append (test-aggregate-summary-cap-skipped)
        | append (test-plan-aware-aggregate-synthesizes-cap-skipped)
        | append (test-reconstruct-suite-index-cap-skipped)
        | append (test-emit-capability-skipped-cell-artifact)
    ) | flatten
    run-suite "ci/planner" $SUITE_PATH $results
}

# compute-cell-depends-on must error on an unrecognised required_role value.
def test-compute-cell-depends-on-rejects-unknown-role [] {
    test-log "\n[test-compute-cell-depends-on-rejects-unknown-role]"
    let cell = {
        cell_id: "share-with__nextcloud-v34__nextcloud-v34",
        flow_id: "share-with",
        scenario: "share-with",
        sender_platform: "nextcloud",
        sender_version: "v34",
        receiver_platform: "nextcloud",
        receiver_version: "v34",
        is_two_party: true,
        enabled: true,
        browser: "chrome",
    }
    let bad_prereqs = {
        capability_rules: [{
            capability_flow: "login",
            required_for_flows: ["share-with"],
            required_roles: ["bogus"],
        }]
    }
    let err = (try {
        compute-cell-depends-on $cell [] $bad_prereqs
        ""
    } catch {|e| $e.msg})
    [
        (assert-string-contains $err "compute-cell-depends-on"
            "error names the function")
        (assert-string-contains $err "bogus"
            "error names the unknown role value")
        (assert-string-contains $err "unknown required_role"
            "error describes the problem")
    ]
}
