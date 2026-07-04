# setup-run-context tuple identity persistence tests.
# Run: nu scripts/tests/services/context.nu

const SUITE_PATH = path self

use ../../lib/services/context.nu [setup-run-context]
use ../../lib/domain/core/ocmts-root.nu [get-ocmts-root]
use ../../lib/run/execution-id.nu [execution-temp-path]
use ../../lib/tests/assert.nu *
use ../../lib/tests/runner.nu [run-suite]

const FIXTURE_EXEC_ID = "20260101t000000-cccccccc"

def test-setup-run-context-persists-matrix-key [] {
    test-log "\n[test-setup-run-context-persists-matrix-key]"
    let docker_check = (try {
        ^docker version | complete
    } catch {
        {exit_code: 127, stdout: "", stderr: ""}
    })
    if $docker_check.exit_code != 0 {
        test-log "  skip: no docker daemon for subnet preflight"
        return [(SKIP "setup-run-context matrix_key: no docker daemon for subnet preflight")]
    }
    let root = (get-ocmts-root)
    let ctx = (
        setup-run-context "login" "nextcloud" "v32" "chrome" false
            --execution-id $FIXTURE_EXEC_ID
    )
    let cell_meta = (open ($ctx.artifacts_base | path join "meta/cell.json"))
    let run_meta = (open ($ctx.artifacts_base | path join "meta/run.json"))
    let runner_ci = (open -r ($ctx.artifacts_base | path join "compose/inputs/runner-ci.yml"))
    let results = [
        (assert-eq ($ctx.cell.matrix_key? | default "") "login__nextcloud"
            "setup-run-context cell record has matrix_key")
        (assert-eq ($cell_meta.matrix_key? | default "") "login__nextcloud"
            "setup-run-context persists matrix_key in meta/cell.json")
        (assert-eq ($run_meta.matrix_key? | default "") "login__nextcloud"
            "setup-run-context persists matrix_key in meta/run.json")
        (assert-truthy (not ("scenario_module" in ($cell_meta | columns)))
            "setup-run-context cell.json omits scenario_module")
        (assert-string-contains $runner_ci "cypress/e2e/login/index.cy.ts"
            "setup-run-context derives Cypress spec path from flow_id")
    ]
    rm -rf $ctx.artifacts_base
    rm -rf (execution-temp-path $FIXTURE_EXEC_ID)
    let marker = ($root | path join "artifacts" "login" "nextcloud-v32" "LAST_EXECUTION_ID")
    if ($marker | path exists) {
        rm $marker
    }
    $results
}

def main [] {
    test-log "=== services/context Tests ==="
    let results = (
        (test-setup-run-context-persists-matrix-key)
    ) | flatten
    run-suite "services/context" $SUITE_PATH $results
}
