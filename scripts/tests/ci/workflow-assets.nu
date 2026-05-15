# Flow-asset file and content behavior tests.
# Covers: build-flow-assets file paths, JSON content validity,
# pretty-printing, flow separation, and per-flow asset coherence.
# Run: nu scripts/tests/ci/workflow-assets.nu
# Returns exit 0 on all pass, exit 1 with details on failure.

const SUITE_PATH = path self

use ../../lib/ci/planner.nu [plan-suite]
use ../../lib/ci/workflow-gen.nu [
    build-ci-matrix-yml
    build-flow-assets
]
use ../../lib/tests/assert.nu *
use ../../lib/tests/fixtures.nu [make-cell]
use ../../lib/tests/runner.nu [run-suite]
use ./fixtures.nu [fixture-rules fixture-prereqs fixture-flow-caps]

# Fixture: plan with a share-with cell that depends on two distinct login cells
# (sender=nextcloud-v34, receiver=nextcloud-v33 -> needs login for both).
def fixture-plan-with-multi-dep [] {
    {
        suite_id: "multi-dep-suite",
        cells: [
            (make-cell {
                cell_id: "login__nextcloud-v33",
                artifact_name: "cell-login-nextcloud-v33",
                sender_version: "v33",
                execution_id: "exec-001",
                capabilities_produced: ["login__nextcloud-v33"],
            }),
            (make-cell {
                cell_id: "login__nextcloud-v34",
                artifact_name: "cell-login-nextcloud-v34",
                execution_id: "exec-002",
                capabilities_produced: ["login__nextcloud-v34"],
            }),
            (make-cell {
                cell_id: "share-with__nextcloud-v34__nextcloud-v33",
                artifact_name: "cell-share-with-nextcloud-v34-nextcloud-v33",
                scenario: "share-with",
                flow_id: "share-with",
                receiver_platform: "nextcloud",
                receiver_version: "v33",
                is_two_party: true,
                execution_id: "exec-003",
                depends_on: ["login__nextcloud-v34" "login__nextcloud-v33"],
                capabilities_produced: [],
            }),
        ]
    }
}

# ---- tests ----

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
    let flow_assets = (build-flow-assets $plan)
    # Each asset path basename must match its flow id.
    let paths_match = ($flow_assets | all {|a|
        let flow_id = ($a.path | path basename | str replace ".json" "")
        $a.path | str contains $flow_id
    })
    [
        (assert-truthy $paths_match
            "each asset file basename matches the flow_id it contains cells for")
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

def test-asset-cell-display-name-present [] {
    test-log "\n[test-asset-cell-display-name-present]"
    let rules = fixture-rules
    let prereqs = fixture-prereqs
    let plan = (plan-suite $rules $prereqs (fixture-flow-caps) {})
    let flow_assets = (build-flow-assets $plan)
    let all_cells = ($flow_assets | each {|a| $a.content | from json} | flatten)
    [
        (assert-truthy (not ($all_cells | is-empty))
            "assets have at least one cell")
        (assert-truthy ($all_cells | all {|c| (($c.display_name? | default "") | str length) > 0})
            "every cell in asset JSON has a non-empty display_name")
    ]
}

def test-asset-display-name-one-party-format [] {
    test-log "\n[test-asset-display-name-one-party-format]"
    let rules = fixture-rules
    let prereqs = fixture-prereqs
    let plan = (plan-suite $rules $prereqs (fixture-flow-caps) {})
    let flow_assets = (build-flow-assets $plan)
    let login_asset_list = ($flow_assets | where {|a| ($a.path | path basename) == "login.json"})
    let login_cells = if not ($login_asset_list | is-empty) {
        $login_asset_list | first | get content | from json
    } else { [] }
    let target_cell_list = ($login_cells | where cell_id == "login__nextcloud-v33")
    [
        (assert-truthy (not ($target_cell_list | is-empty))
            "login asset has a cell with cell_id login__nextcloud-v33")
        (assert-eq ($target_cell_list | first | get display_name)
            "login / test / nextcloud v33"
            "one-party display_name is <flow_id> / test / <sender_platform> <sender_version>")
        (assert-truthy (not (($target_cell_list | first | get display_name) | str contains " -> "))
            "one-party display_name has no -> arrow")
    ]
}

def test-asset-display-name-two-party-format [] {
    test-log "\n[test-asset-display-name-two-party-format]"
    let plan = fixture-plan-with-multi-dep
    let flow_assets = (build-flow-assets $plan)
    let share_asset_list = ($flow_assets | where {|a| ($a.path | path basename) | str starts-with "share-with"})
    let share_cells = if not ($share_asset_list | is-empty) {
        $share_asset_list | first | get content | from json
    } else { [] }
    let two_party_cell_list = ($share_cells | where cell_id == "share-with__nextcloud-v34__nextcloud-v33")
    [
        (assert-truthy (not ($two_party_cell_list | is-empty))
            "share-with asset has the two-party cell")
        (assert-eq ($two_party_cell_list | first | get display_name)
            "share-with / test / nextcloud v34 to nextcloud v33"
            "two-party display_name is <flow_id> / test / <sender_platform> <sv> to <receiver_platform> <rv>")
    ]
}

# Regression: the production prerequisites config must generate non-empty
# cell_depends_on for share-with cells. Loads config/ci/prerequisites.nuon
# directly so any capability_flow mismatch is caught here rather than masked
# by the fixture-prereqs shim (which already uses the correct flow id).
def test-prod-prereqs-share-with-cell-depends-on [] {
    test-log "\n[test-prod-prereqs-share-with-cell-depends-on]"
    let repo_root = ($SUITE_PATH | path dirname | path join ".." ".." ".." | path expand)
    let prod_prereqs = (open ($repo_root | path join "config" "ci" "prerequisites.nuon"))
    let rules = fixture-rules
    let plan = (plan-suite $rules $prod_prereqs (fixture-flow-caps) {})
    let flow_assets = (build-flow-assets $plan)
    let share_asset_list = ($flow_assets | where {|a| ($a.path | path basename) == "share-with.json"})
    let share_cells = if not ($share_asset_list | is-empty) {
        $share_asset_list | first | get content | from json
    } else { [] }
    let share_cell_list = ($share_cells | where cell_id == "share-with__nextcloud-v34__nextcloud-v34")
    let cell_dep = if not ($share_cell_list | is-empty) {
        ($share_cell_list | first).cell_depends_on? | default ""
    } else { "" }
    [
        (assert-truthy (not ($share_cells | is-empty))
            "prod prereqs: share-with asset has cells")
        (assert-truthy (not ($share_cell_list | is-empty))
            "prod prereqs: share-with asset has nextcloud-v34->nextcloud-v34 cell")
        (assert-truthy (($cell_dep | str length) > 0)
            "prod prereqs: share-with cell_depends_on is non-empty (capability_flow in prerequisites.nuon must match producer flow_id 'login')")
        (assert-truthy ($cell_dep | str contains "cell-login-nextcloud-v34")
            "prod prereqs: share-with cell_depends_on references cell-login-nextcloud-v34 artifact")
    ]
}

def main [] {
    test-log "=== CI workflow-assets tests ==="
    let results = (
        (test-asset-file-paths)
        | append (test-asset-content-valid-json)
        | append (test-asset-content-is-pretty-printed)
        | append (test-matrix-flow-job-asset-path-matches-flow-id)
        | append (test-flow-separation)
        | append (test-multi-dep-cell-depends-on)
        | append (test-asset-cell-display-name-present)
        | append (test-asset-display-name-one-party-format)
        | append (test-asset-display-name-two-party-format)
        | append (test-prod-prereqs-share-with-cell-depends-on)
    ) | flatten
    run-suite "ci/workflow-assets" $SUITE_PATH $results
}
