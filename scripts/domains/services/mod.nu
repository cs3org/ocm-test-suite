# Services domain: docker compose lifecycle management.

use ../../lib/compose-validate.nu [validate-compose-strict]
use ../../lib/run-metadata.nu [
    write-terminal-run
    write-compact-result
    update-run-lifecycle
    utc-now
]
use ../../lib/execution-id.nu [execution-artifacts-path]
use ../../lib/cell.nu [compute-cell]
use ../../lib/artifacts-init.nu [read-last-execution-id]
use ../../lib/domain/core/ocmts-root.nu [get-ocmts-root]
use ../../lib/mitm-peers.nu [write-mitm-peers]
use ../../lib/services/cypress-run.nu [run-cypress-ci]
use ../../lib/services/postrun-artifacts.nu [collect-run-artifacts]
use ../../lib/services/context.nu [setup-run-context]
use ../../lib/services/compose-files.nu [build-f-args write-active-files read-active-compose-files]
use ../../lib/services/lifecycle.nu [
    cleanup-temp
    ensure-network-gone
    cleanup-down
    overwrite-cleanup-failed
    do-compose-up
    do-compose-down
]
use ../../lib/publish-envelope.nu [publish-envelope-safe emit-publish-envelope]

def main [] {
    print "Usage: nu scripts/ocmts.nu services <verb> [flags]"
    print ""
    print "Verbs:"
    print "  up       Bring up platform+helper services for a cell"
    print "  down     Tear down services for a cell"
    print ""
    print "Shortcuts:"
    print "  up run   Bring up + run tests (headless) + collect artifacts + tear down"
    print "  up open  Bring up + start dev Cypress workspace (no auto-down)"
}

def "main up" [
    --scenario: string,
    --sender-platform: string,
    --sender-version: string,
    --receiver-platform: string = "",
    --receiver-version: string = "",
    --browser: string = "chrome",
    --no-video,
    --preserve-temp,
] {
    let ctx = (setup-run-context
        $scenario $sender_platform $sender_version $browser (not $no_video)
        $receiver_platform $receiver_version)
    let base_files = ([$ctx.base_yml] | append (
        $ctx.base_overlay_fnames | each {|f| $ctx.compose_d | path join $f}
    ))
    let f_args = (build-f-args $base_files)
    write-active-files $ctx.artifacts_base $ctx.base_yml $ctx.base_overlay_fnames
    try {
        (validate-compose-strict $base_files $ctx.stack_id
            ($ctx.artifacts_base | path join "compose" "compose.resolved.yml"))
    } catch {|e|
        let finished_at = (utc-now)
        (write-terminal-run $ctx.artifacts_base $ctx.execution_id
            $ctx.cell.cell_id $ctx.cell.artifact_name
            $ctx.started_at $finished_at "infra-failed" 1 $ctx.stack_id
            $ctx.images --phase "compose-validate-base" --fail-error $e.msg)
        (write-compact-result $ctx.artifacts_base $ctx.execution_id
            $ctx.cell.cell_id "infra-failed" 1 $finished_at)
        publish-envelope-safe $ctx.artifacts_base
        cleanup-temp $ctx.execution_id $preserve_temp
        error make {msg: $"Compose validation failed: ($e.msg)"}
    }
    let wait_services = if $ctx.is_two_party { ["sender" "receiver" "mitm"] } else { ["platform"] }
    try {
        ^docker compose ...$f_args -p $ctx.stack_id up -d --wait ...$wait_services
    } catch {|e|
        let finished_at = (utc-now)
        let up_exit = ($env.LAST_EXIT_CODE? | default 1)
        (write-terminal-run $ctx.artifacts_base $ctx.execution_id
            $ctx.cell.cell_id $ctx.cell.artifact_name
            $ctx.started_at $finished_at "infra-failed" $up_exit $ctx.stack_id
            $ctx.images --phase "platform-up" --fail-error $e.msg)
        (write-compact-result $ctx.artifacts_base $ctx.execution_id
            $ctx.cell.cell_id "infra-failed" $up_exit $finished_at)
        let down_fail = (try { cleanup-down $base_files $ctx.stack_id $ctx.artifacts_base; null } catch {|ce| $ce.msg})
        if $down_fail != null {
            overwrite-cleanup-failed $ctx $preserve_temp $down_fail $"platform-up failed: ($e.msg)"
        }
        publish-envelope-safe $ctx.artifacts_base
        cleanup-temp $ctx.execution_id $preserve_temp
        error make {msg: $"docker compose up failed: ($e.msg)"}
    }
    update-run-lifecycle $ctx.artifacts_base "active" --phase "platform-up"
    print $"Stack up. execution_id=($ctx.execution_id) stack_id=($ctx.stack_id)"
    print $"Artifacts: ($ctx.artifacts_base)"
}

def "main up run" [
    --scenario: string,
    --sender-platform: string,
    --sender-version: string,
    --receiver-platform: string = "",
    --receiver-version: string = "",
    --browser: string = "chrome",
    --no-video,
    --preserve-temp,
    --keep-up,
    --verbose,     # Show all docker compose output; default is quiet mode
] {
    let ctx = (setup-run-context
        $scenario $sender_platform $sender_version $browser (not $no_video)
        $receiver_platform $receiver_version)
    let base_files = ([$ctx.base_yml] | append (
        $ctx.base_overlay_fnames | each {|f| $ctx.compose_d | path join $f}
    ))
    let f_args_base = (build-f-args $base_files)
    let run_files = ($base_files | append ($ctx.compose_d | path join "runner-ci.yml"))
    let f_args_run = (build-f-args $run_files)
    write-active-files $ctx.artifacts_base $ctx.base_yml $ctx.base_overlay_fnames

    # Step 1: validate base file set strictly before touching Docker.
    try {
        (validate-compose-strict $base_files $ctx.stack_id
            ($ctx.artifacts_base | path join "compose" "compose.resolved.yml"))
    } catch {|e|
        let finished_at = (utc-now)
        (write-terminal-run $ctx.artifacts_base $ctx.execution_id
            $ctx.cell.cell_id $ctx.cell.artifact_name
            $ctx.started_at $finished_at "infra-failed" 1 $ctx.stack_id
            $ctx.images --phase "compose-validate-base" --fail-error $e.msg)
        (write-compact-result $ctx.artifacts_base $ctx.execution_id
            $ctx.cell.cell_id "infra-failed" 1 $finished_at)
        publish-envelope-safe $ctx.artifacts_base
        cleanup-temp $ctx.execution_id $preserve_temp
        error make {msg: $"Compose base validation failed: ($e.msg)"}
    }

    # Bring up platform services; quiet by default, verbose with --verbose.
    let wait_services = if $ctx.is_two_party { ["sender" "receiver" "mitm"] } else { ["platform"] }
    if not $verbose { print "Starting services..." }
    let up_err = (do-compose-up $f_args_base $ctx.stack_id $wait_services $verbose)
    if $up_err != null {
        let finished_at = (utc-now)
        let up_exit = $up_err.exit_code
        (write-terminal-run $ctx.artifacts_base $ctx.execution_id
            $ctx.cell.cell_id $ctx.cell.artifact_name
            $ctx.started_at $finished_at "infra-failed" $up_exit $ctx.stack_id
            $ctx.images --phase "platform-up" --fail-error $up_err.msg)
        (write-compact-result $ctx.artifacts_base $ctx.execution_id
            $ctx.cell.cell_id "infra-failed" $up_exit $finished_at)
        if not $keep_up {
            let down_fail = (try { cleanup-down $base_files $ctx.stack_id $ctx.artifacts_base; null } catch {|ce| $ce.msg})
            if $down_fail != null {
                overwrite-cleanup-failed $ctx $preserve_temp $down_fail $"platform-up failed: ($up_err.msg)"
            }
        }
        publish-envelope-safe $ctx.artifacts_base
        cleanup-temp $ctx.execution_id $preserve_temp
        error make {msg: $"docker compose up platform failed: ($up_err.msg)"}
    }

    # Write peers.json before Cypress so it exists even if tests fail.
    if $ctx.is_two_party {
        try {
            write-mitm-peers $ctx.artifacts_base $ctx.stack_id $ctx.cell
        } catch {|e|
            print $"WARNING: write-mitm-peers failed: ($e.msg)"
        }
    }

    # Step 2: validate runner-ci file set strictly before running Cypress.
    try {
        (validate-compose-strict $run_files $ctx.stack_id
            ($ctx.artifacts_base | path join "compose" "compose.resolved.run.yml"))
    } catch {|e|
        let finished_at = (utc-now)
        (write-terminal-run $ctx.artifacts_base $ctx.execution_id
            $ctx.cell.cell_id $ctx.cell.artifact_name
            $ctx.started_at $finished_at "infra-failed" 1 $ctx.stack_id
            $ctx.images --phase "compose-validate-runner-ci" --fail-error $e.msg)
        (write-compact-result $ctx.artifacts_base $ctx.execution_id
            $ctx.cell.cell_id "infra-failed" 1 $finished_at)
        if not $keep_up {
            let down_fail = (try { cleanup-down $base_files $ctx.stack_id $ctx.artifacts_base; null } catch {|ce| $ce.msg})
            if $down_fail != null {
                overwrite-cleanup-failed $ctx $preserve_temp $down_fail $"runner-ci validation failed: ($e.msg)"
            }
        }
        publish-envelope-safe $ctx.artifacts_base
        cleanup-temp $ctx.execution_id $preserve_temp
        error make {msg: $"Compose runner-ci validation failed: ($e.msg)"}
    }
    write-active-files $ctx.artifacts_base $ctx.base_yml $ctx.base_overlay_fnames "runner-ci.yml"

    print $"Running tests for ($ctx.cell.cell_id) [execution_id=($ctx.execution_id)]..."
    let cy = (run-cypress-ci $ctx.artifacts_base $f_args_run $ctx.stack_id $verbose)
    let cypress_exit = $cy.exit_code
    let cypress_status = if $cypress_exit == 0 { "passed" } else { "failed" }

    collect-run-artifacts $ctx.artifacts_base $ctx.stack_id $run_files $ctx.is_two_party

    mut down_err = null
    if not $keep_up {
        print "Tearing down services..."
        let down_files = (read-active-compose-files $ctx.artifacts_base $ctx.base_yml)
        let f_args_down = (build-f-args $down_files)
        let down_validate_err = (try {
            (validate-compose-strict $down_files $ctx.stack_id
                ($ctx.artifacts_base | path join "compose" "compose.resolved.down.yml"))
            null
        } catch {|ve|
            $ve.msg
        })
        $down_err = if $down_validate_err != null {
            $"compose down validation failed: ($down_validate_err)"
        } else {
            let dc_err = (do-compose-down $f_args_down $ctx.stack_id $verbose)
            if $dc_err != null {
                $dc_err
            } else {
                try { ensure-network-gone $ctx.stack_id; null } catch {|e| $e.msg}
            }
        }
    }

    let finished_at = (utc-now)
    if $down_err != null {
        let down_fail_msg = $"cleanup/down failed: ($down_err)"
        (write-terminal-run $ctx.artifacts_base $ctx.execution_id
            $ctx.cell.cell_id $ctx.cell.artifact_name
            $ctx.started_at $finished_at "cleanup-failed" 1 $ctx.stack_id
            $ctx.images --phase "compose-down"
            --fail-error $"($down_fail_msg) [cypress: status=($cypress_status) exit=($cypress_exit)]")
        (write-compact-result $ctx.artifacts_base $ctx.execution_id
            $ctx.cell.cell_id "cleanup-failed" 1 $finished_at)
        publish-envelope-safe $ctx.artifacts_base
        cleanup-temp $ctx.execution_id $preserve_temp
        error make {msg: $down_fail_msg}
    }

    (write-terminal-run $ctx.artifacts_base $ctx.execution_id
        $ctx.cell.cell_id $ctx.cell.artifact_name
        $ctx.started_at $finished_at $cypress_status $cypress_exit $ctx.stack_id
        $ctx.images)
    (write-compact-result $ctx.artifacts_base $ctx.execution_id
        $ctx.cell.cell_id $cypress_status $cypress_exit $finished_at)
    emit-publish-envelope $ctx.artifacts_base
    cleanup-temp $ctx.execution_id $preserve_temp
    print $"Done. status=($cypress_status) execution_id=($ctx.execution_id)"
    print $"Artifacts: ($ctx.artifacts_base)"
    exit $cypress_exit
}

def "main up open" [
    --scenario: string,
    --sender-platform: string,
    --sender-version: string,
    --receiver-platform: string = "",
    --receiver-version: string = "",
    --browser: string = "chrome",
    --no-video,
    --preserve-temp,
] {
    let ctx = (setup-run-context
        $scenario $sender_platform $sender_version $browser (not $no_video)
        $receiver_platform $receiver_version)
    let base_files = ([$ctx.base_yml] | append (
        $ctx.base_overlay_fnames | each {|f| $ctx.compose_d | path join $f}
    ))
    let f_args_base = (build-f-args $base_files)

    try {
        (validate-compose-strict $base_files $ctx.stack_id
            ($ctx.artifacts_base | path join "compose" "compose.resolved.yml"))
    } catch {|e|
        let finished_at = (utc-now)
        (write-terminal-run $ctx.artifacts_base $ctx.execution_id
            $ctx.cell.cell_id $ctx.cell.artifact_name
            $ctx.started_at $finished_at "infra-failed" 1 $ctx.stack_id
            $ctx.images --phase "compose-validate-base" --fail-error $e.msg)
        (write-compact-result $ctx.artifacts_base $ctx.execution_id
            $ctx.cell.cell_id "infra-failed" 1 $finished_at)
        publish-envelope-safe $ctx.artifacts_base
        cleanup-temp $ctx.execution_id $preserve_temp
        error make {msg: $"Compose validation failed: ($e.msg)"}
    }
    let wait_services = if $ctx.is_two_party { ["sender" "receiver" "mitm"] } else { ["platform"] }
    try {
        ^docker compose ...$f_args_base -p $ctx.stack_id up -d --wait ...$wait_services
    } catch {|e|
        let finished_at = (utc-now)
        let up_exit = ($env.LAST_EXIT_CODE? | default 1)
        (write-terminal-run $ctx.artifacts_base $ctx.execution_id
            $ctx.cell.cell_id $ctx.cell.artifact_name
            $ctx.started_at $finished_at "infra-failed" $up_exit $ctx.stack_id
            $ctx.images --phase "platform-up" --fail-error $e.msg)
        (write-compact-result $ctx.artifacts_base $ctx.execution_id
            $ctx.cell.cell_id "infra-failed" $up_exit $finished_at)
        let down_fail = (try { cleanup-down $base_files $ctx.stack_id $ctx.artifacts_base; null } catch {|ce| $ce.msg})
        if $down_fail != null {
            overwrite-cleanup-failed $ctx $preserve_temp $down_fail $"platform-up failed: ($e.msg)"
        }
        publish-envelope-safe $ctx.artifacts_base
        cleanup-temp $ctx.execution_id $preserve_temp
        error make {msg: $"Failed to start platform services: ($e.msg)"}
    }
    write-active-files $ctx.artifacts_base $ctx.base_yml $ctx.base_overlay_fnames
    print $"Stack up. execution_id=($ctx.execution_id) stack_id=($ctx.stack_id)"

    let dev_files = ($base_files | append ($ctx.compose_d | path join "runner-dev.yml"))
    let f_args_dev = (build-f-args $dev_files)
    try {
        (validate-compose-strict $dev_files $ctx.stack_id
            ($ctx.artifacts_base | path join "compose" "compose.resolved.dev.yml"))
    } catch {|e|
        let finished_at = (utc-now)
        (write-terminal-run $ctx.artifacts_base $ctx.execution_id
            $ctx.cell.cell_id $ctx.cell.artifact_name
            $ctx.started_at $finished_at "infra-failed" 1 $ctx.stack_id
            $ctx.images --phase "compose-validate-dev" --fail-error $e.msg)
        (write-compact-result $ctx.artifacts_base $ctx.execution_id
            $ctx.cell.cell_id "infra-failed" 1 $finished_at)
        let down_fail = (try { cleanup-down $base_files $ctx.stack_id $ctx.artifacts_base; null } catch {|ce| $ce.msg})
        if $down_fail != null {
            overwrite-cleanup-failed $ctx $preserve_temp $down_fail $"dev validation failed: ($e.msg)"
        }
        publish-envelope-safe $ctx.artifacts_base
        cleanup-temp $ctx.execution_id $preserve_temp
        error make {msg: $"Compose dev validation failed: ($e.msg)"}
    }
    write-active-files $ctx.artifacts_base $ctx.base_yml $ctx.base_overlay_fnames "runner-dev.yml"
    try {
        ^docker compose ...$f_args_dev -p $ctx.stack_id up -d cypress_dev
    } catch {|e|
        let finished_at = (utc-now)
        let up_exit = ($env.LAST_EXIT_CODE? | default 1)
        (write-terminal-run $ctx.artifacts_base $ctx.execution_id
            $ctx.cell.cell_id $ctx.cell.artifact_name
            $ctx.started_at $finished_at "infra-failed" $up_exit $ctx.stack_id
            $ctx.images --phase "cypress-dev-up" --fail-error $e.msg)
        (write-compact-result $ctx.artifacts_base $ctx.execution_id
            $ctx.cell.cell_id "infra-failed" $up_exit $finished_at)
        let down_fail = (try { cleanup-down $dev_files $ctx.stack_id $ctx.artifacts_base; null } catch {|ce| $ce.msg})
        if $down_fail != null {
            overwrite-cleanup-failed $ctx $preserve_temp $down_fail $"cypress_dev up failed: ($e.msg)"
        }
        publish-envelope-safe $ctx.artifacts_base
        cleanup-temp $ctx.execution_id $preserve_temp
        error make {msg: $"Failed to start cypress_dev: ($e.msg)"}
    }

    let port_result = (try {
        ^docker compose ...$f_args_dev -p $ctx.stack_id port cypress_dev 6901 | complete
    } catch {|e|
        {exit_code: 1, stdout: "", stderr: $e.msg}
    })
    if $port_result.exit_code != 0 {
        let finished_at = (utc-now)
        let port_err = if ($port_result.stderr | str trim | is-empty) {
            "port lookup returned non-zero exit"
        } else {
            $port_result.stderr | str trim
        }
        (write-terminal-run $ctx.artifacts_base $ctx.execution_id
            $ctx.cell.cell_id $ctx.cell.artifact_name
            $ctx.started_at $finished_at "infra-failed" 1 $ctx.stack_id
            $ctx.images --phase "cypress-dev-up" --fail-error $port_err)
        (write-compact-result $ctx.artifacts_base $ctx.execution_id
            $ctx.cell.cell_id "infra-failed" 1 $finished_at)
        let down_fail = (try { cleanup-down $dev_files $ctx.stack_id $ctx.artifacts_base; null } catch {|ce| $ce.msg})
        if $down_fail != null {
            overwrite-cleanup-failed $ctx $preserve_temp $down_fail $"port lookup failed: ($port_err)"
        }
        publish-envelope-safe $ctx.artifacts_base
        cleanup-temp $ctx.execution_id $preserve_temp
        error make {msg: $"cypress_dev port lookup failed: ($port_err)"}
    }
    let host_port_raw = ($port_result.stdout | str trim)
    let host_port = ($host_port_raw | split row ":" | last | str trim)
    if (($host_port | is-empty) or not ($host_port =~ '^\d+$')) {
        let finished_at = (utc-now)
        let port_err = $"port lookup returned invalid port: '($host_port_raw)'"
        (write-terminal-run $ctx.artifacts_base $ctx.execution_id
            $ctx.cell.cell_id $ctx.cell.artifact_name
            $ctx.started_at $finished_at "infra-failed" 1 $ctx.stack_id
            $ctx.images --phase "cypress-dev-up" --fail-error $port_err)
        (write-compact-result $ctx.artifacts_base $ctx.execution_id
            $ctx.cell.cell_id "infra-failed" 1 $finished_at)
        let down_fail = (try { cleanup-down $dev_files $ctx.stack_id $ctx.artifacts_base; null } catch {|ce| $ce.msg})
        if $down_fail != null {
            overwrite-cleanup-failed $ctx $preserve_temp $down_fail $"port lookup failed: ($port_err)"
        }
        publish-envelope-safe $ctx.artifacts_base
        cleanup-temp $ctx.execution_id $preserve_temp
        error make {msg: $"cypress_dev port lookup returned invalid port: ($port_err)"}
    }
    update-run-lifecycle $ctx.artifacts_base "open" --phase "cypress-dev-up"
    print $"cypress_dev ready. Open: http://localhost:($host_port)"
    print "Run 'services down' to tear down when done."
}

def "main down" [
    --scenario: string,
    --sender-platform: string,
    --sender-version: string,
    --receiver-platform: string = "",
    --receiver-version: string = "",
    --execution-id: string = "",
    --preserve-temp,
] {
    let root = get-ocmts-root
    let cell = (compute-cell
        $scenario $sender_platform $sender_version "chrome"
        $receiver_platform $receiver_version)
    let exec_id = if ($execution_id | is-empty) {
        read-last-execution-id $cell.artifact_name
    } else {
        $execution_id
    }
    let artifacts_base = (execution-artifacts-path $root $cell.artifact_name $exec_id)

    let stack_id_file = ($artifacts_base | path join "compose" "stack_id.txt")
    if not ($stack_id_file | path exists) {
        error make {msg: $"No stack_id found for execution_id=($exec_id). Artifacts may be missing."}
    }
    let stack_id = (open --raw $stack_id_file | str trim)

    print $"Tearing down ($cell.cell_id) [stack_id=($stack_id)]..."
    let base_yml = ($root | path join "config/compose/base.yml")
    let active_files_path = ($artifacts_base | path join "compose" "active-files.txt")
    if not ($active_files_path | path exists) {
        print "WARNING: active-files.txt not found; using base-only file set (legacy artifacts)"
    }
    let down_files = (read-active-compose-files $artifacts_base $base_yml)
    let f_args_down = (build-f-args $down_files)
    try {
        (validate-compose-strict $down_files $stack_id
            ($artifacts_base | path join "compose" "compose.resolved.down.yml"))
    } catch {|ve|
        cleanup-temp $exec_id $preserve_temp
        let finished_at = (utc-now)
        (update-run-lifecycle $artifacts_base "down-failed" --phase "compose-down"
            --finished-at $finished_at --exit-code 1 --error $ve.msg)
        error make {msg: $"cleanup/down failed: down file set validation failed: ($ve.msg)"}
    }
    let down_err = (try {
        ^docker compose ...$f_args_down -p $stack_id down --volumes
        ensure-network-gone $stack_id
        null
    } catch {|e|
        $e.msg
    })

    cleanup-temp $exec_id $preserve_temp
    let finished_at = (utc-now)
    if $down_err != null {
        (update-run-lifecycle $artifacts_base "down-failed" --phase "compose-down"
            --finished-at $finished_at --exit-code 1 --error $down_err)
        error make {msg: $"cleanup/down failed: ($down_err)"}
    }
    (update-run-lifecycle $artifacts_base "stopped" --phase "compose-down"
        --finished-at $finished_at)
    print $"Services down. execution_id=($exec_id) status=stopped"
}
