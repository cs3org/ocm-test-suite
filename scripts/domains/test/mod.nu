# Test domain: test execution against an already-up stack.

use ../../lib/cell.nu [compute-cell validate-cell-rules assert-scenario-enabled]
use ../../lib/matrix-expand.nu [expand-version-pairs]
use ../../lib/artifacts-init.nu [read-last-execution-id]
use ../../lib/compose-validate.nu [validate-compose-strict]
use ../../lib/execution-id.nu [execution-artifacts-path]
use ../../lib/run-metadata.nu [write-terminal-run write-compact-result utc-now]
use ../../lib/publish-envelope.nu [publish-envelope-safe emit-publish-envelope]
use ../../lib/domain/core/ocmts-root.nu [get-ocmts-root]
use ../../lib/services/cypress-run.nu [run-cypress-ci]
use ../../lib/services/compose-files.nu [build-f-args build-run-files]
use ../../lib/suite-index.nu [new-suite-id init-suite-record update-latest-suite-id finish-suite-record]

# Returns true if docker compose reports the primary platform service as running.
def stack-platform-running [f_args: list<string>, stack_id: string, is_two_party: bool] {
    let check_svc = if $is_two_party { "sender" } else { "platform" }
    let result = (try {
        ^docker compose ...$f_args -p $stack_id ps --status running --services | complete
    } catch {
        {exit_code: 1, stdout: "", stderr: ""}
    })
    if $result.exit_code != 0 {
        false
    } else {
        let running = ($result.stdout | lines | each {|l| $l | str trim} | where {|l| not ($l | is-empty)})
        $check_svc in $running
    }
}

def main [] {
    print "Usage: nu scripts/ocmts.nu test <verb> [flags]"
    print ""
    print "Verbs:"
    print "  run     Run Cypress tests headless against an already-up stack"
    print "  suite   Run the full enabled matrix suite sequentially"
    print ""
    print "Notes:"
    print "  Video recording is enabled by default. To opt out, pass --no-video"
    print "  to 'services up', 'services up run', or 'services up open'."
    print "  'test run' reuses the runner-ci.yml overlay pre-rendered by"
    print "  'services up' / 'services up open', so the video setting is"
    print "  inherited from that prior step."
    print ""
    print "  'test run' does NOT tear down services after the test pass."
    print "  Platform service logs (platform container stdout/stderr) are"
    print "  NOT collected automatically by 'test run'. Only the Cypress"
    print "  container output is captured. If you need platform logs,"
    print "  run the following while the stack is still up:"
    print "    nu scripts/ocmts.nu artifacts collect --include-logs ..."
    print "  Platform log collection is otherwise tied to the teardown"
    print "  path ('services up run') which calls 'services down'."
}

def "main run" [
    --scenario: string,
    --sender-platform: string,
    --sender-version: string,
    --receiver-platform: string = "",
    --receiver-version: string = "",
    --browser: string = "chrome",
    --execution-id: string = "",
    --verbose,     # Show all docker compose output; default is quiet mode
] {
    let root = get-ocmts-root
    assert-scenario-enabled $scenario
    let flow_id = (validate-cell-rules
        $scenario $sender_platform $sender_version $browser
        $receiver_platform $receiver_version)
    let cell = (compute-cell
        $scenario $sender_platform $sender_version $browser
        $receiver_platform $receiver_version $flow_id)
    let exec_id = if ($execution_id | is-empty) {
        read-last-execution-id $cell.artifact_name
    } else {
        $execution_id
    }
    let artifacts_base = (execution-artifacts-path $root $cell.artifact_name $exec_id)
    let art_compose = ($artifacts_base | path join "compose")
    let stack_id_file = ($art_compose | path join "stack_id.txt")
    if not ($stack_id_file | path exists) {
        error make {msg: $"No stack_id found for execution_id=($exec_id). Run 'services up' first."}
    }
    let stack_id = (open --raw $stack_id_file | str trim)
    let base_yml = ($root | path join "config/compose/base.yml")

    let run_meta_path = ($artifacts_base | path join "meta/run.json")
    if not ($run_meta_path | path exists) {
        error make {msg: $"No run.json found for execution_id=($exec_id). Run 'services up' first."}
    }
    let prev_run = (open $run_meta_path)
    let cur_status = ($prev_run.status? | default "")
    let terminal_statuses = ["stopped" "infra-failed" "cleanup-failed" "down-failed"]
    let allowed_statuses = ["active" "open" "passed" "failed"]
    if $cur_status in $terminal_statuses {
        error make {msg: $"Cannot run tests: execution ($exec_id) has terminal status '($cur_status)'. Start a new run with 'services up'."}
    } else if not ($cur_status in $allowed_statuses) {
        error make {msg: $"Cannot run tests: execution ($exec_id) has unexpected status '($cur_status)'."}
    }
    if ($cur_status in ["passed" "failed"]) {
        let active_files_path = ($art_compose | path join "active-files.txt")
        if not ($active_files_path | path exists) {
            error make {msg: $"Cannot rerun tests: execution ($exec_id) has status '($cur_status)' but active-files marker not found. Use 'services up' for a new run."}
        }
        let check_files = (open --raw $active_files_path | lines | where {|l| not ($l | is-empty)})
        let check_f_args = (build-f-args $check_files)
        if not (stack-platform-running $check_f_args $stack_id $cell.is_two_party) {
            error make {msg: $"Cannot rerun tests: execution ($exec_id) has status '($cur_status)' but platform service is not running. Run 'services down' then 'services up' for a new run."}
        }
    }
    let started_at = ($prev_run.started_at? | default (utc-now))

    let cell_meta = (open ($artifacts_base | path join "meta/cell.json"))
    let images = ($cell_meta.images? | default null)

    let run_files = (build-run-files $artifacts_base $base_yml)
    let f_args = (build-f-args $run_files)

    # Validate runner-ci file set strictly before running Cypress.
    try {
        (validate-compose-strict $run_files $stack_id
            ($art_compose | path join "compose.resolved.run.yml"))
    } catch {|e|
        let finished_at = (utc-now)
        (write-terminal-run $artifacts_base $exec_id $cell.cell_id
            $cell.artifact_name $started_at $finished_at "infra-failed" 1 $stack_id
            $images --phase "compose-validate-runner-ci" --fail-error $e.msg)
        (write-compact-result $artifacts_base $exec_id
            $cell.cell_id "infra-failed" 1 $finished_at)
        publish-envelope-safe $artifacts_base
        error make {msg: $"Compose runner-ci validation failed: ($e.msg)"}
    }

    print $"Running tests for ($cell.cell_id) [execution_id=($exec_id)]..."
    let cy = (run-cypress-ci $artifacts_base $f_args $stack_id $verbose)
    let cypress_exit = $cy.exit_code

    let finished_at = (utc-now)
    let status = if $cypress_exit == 0 { "passed" } else { "failed" }

    (write-terminal-run $artifacts_base $exec_id $cell.cell_id
        $cell.artifact_name $started_at $finished_at $status $cypress_exit $stack_id
        $images)
    (write-compact-result $artifacts_base $exec_id
        $cell.cell_id $status $cypress_exit $finished_at)
    emit-publish-envelope $artifacts_base

    exit $cypress_exit
}

# Run the full enabled matrix suite sequentially via `services up run`.
# Reads config/matrix-rules.nuon, expands all cells, filters to enabled only,
# then runs each cell in order. Default: continue after failures.
def "main suite" [
    --suite-id: string = "",  # Override generated suite_id for this run
    --stop-on-fail,           # Stop on first failure (default: continue)
    --continue-on-fail,       # Compat alias: continue after failures (now the default)
    --max: int = 0,           # Limit runs to N cells (0 = unlimited)
    --verbose,                # Pass --verbose to services up run
] {
    let root = get-ocmts-root
    let rules = open ($root | path join "config/matrix-rules.nuon")
    let ocmts_script = ($root | path join "scripts/ocmts.nu")

    let all_cells = ($rules.scenarios | items {|scenario, sc|
        let recv_platform = ($sc.receiver?.platform? | default "")
        let flow_id = ($sc.flow_id? | default $scenario)
        let is_two_party = ($sc.receiver? != null)
        let version_pairs = (expand-version-pairs $sc)
        $version_pairs | each {|vp|
            $sc.browsers | each {|browser|
                let cell_id = if $is_two_party {
                    $"($flow_id)__($sc.sender.platform)-($vp.sender_version)__($recv_platform)-($vp.receiver_version)"
                } else {
                    $"($flow_id)__($sc.sender.platform)-($vp.sender_version)"
                }
                {
                    scenario: $scenario,
                    sender_platform: $sc.sender.platform,
                    sender_version: $vp.sender_version,
                    receiver_platform: $recv_platform,
                    receiver_version: $vp.receiver_version,
                    browser: $browser,
                    enabled: ($sc.enabled? | default false),
                    cell_id: $cell_id,
                }
            }
        } | flatten
    } | flatten)

    let enabled_cells = ($all_cells | where enabled)
    let cells_to_run = if $max > 0 {
        $enabled_cells | first $max
    } else {
        $enabled_cells
    }
    let total = ($cells_to_run | length)

    if $total == 0 {
        print "Suite: no enabled cells to run."
        return
    }

    let eff_suite_id = if ($suite_id | is-empty) { new-suite-id } else { $suite_id }
    print $"Suite: ($total) cell\(s\) to run  suite_id=($eff_suite_id)"

    let cell_ids = ($cells_to_run | each {|c| $c.cell_id})
    (init-suite-record $eff_suite_id "suite" $cell_ids)

    mut passed = 0
    mut failed_cells: list<string> = []

    for cell in $cells_to_run {
        print $"\n--- ($cell.cell_id) ---"
        mut args: list<string> = [
            "services" "up" "run"
            "--scenario" $cell.scenario
            "--sender-platform" $cell.sender_platform
            "--sender-version" $cell.sender_version
            "--browser" $cell.browser
            "--suite-id" $eff_suite_id
            "--suite-kind" "suite"
        ]
        if not ($cell.receiver_platform | is-empty) {
            $args = ($args | append ["--receiver-platform" $cell.receiver_platform])
        }
        if not ($cell.receiver_version | is-empty) {
            $args = ($args | append ["--receiver-version" $cell.receiver_version])
        }
        if $verbose {
            $args = ($args | append ["--verbose"])
        }

        let cell_exit = (try { ^nu $ocmts_script ...$args; 0 } catch {|e| ($e.exit_code? | default 1) })

        if $cell_exit == 0 {
            $passed = $passed + 1
        } else {
            $failed_cells = ($failed_cells | append $cell.cell_id)
            if $stop_on_fail {
                print $"\nStopped on failure: ($cell.cell_id)"
                break
            }
        }
    }

    let failed_count = ($failed_cells | length)
    try {
        finish-suite-record $eff_suite_id $passed $failed_count
    } catch {|e|
        print $"WARNING: finish-suite-record failed: ($e.msg)"
    }
    if $max == 0 {
        update-latest-suite-id $eff_suite_id
    }

    let ran = $passed + $failed_count
    print "\n=== Suite Summary ==="
    print $"suite_id:        ($eff_suite_id)"
    print $"Total scheduled: ($total)"
    print $"Ran:             ($ran)"
    print $"Passed:          ($passed)"
    print $"Failed:          ($failed_count)"

    if not ($failed_cells | is-empty) {
        print "\nFailing cells:"
        for c in $failed_cells {
            print $"  - ($c)"
        }
        exit 1
    }
}
