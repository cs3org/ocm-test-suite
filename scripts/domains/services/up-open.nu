# Bring up services and start dev Cypress workspace (no auto-down).

use ../../lib/compose/validate.nu [validate-compose-strict]
use ../../lib/run/metadata.nu [
    write-terminal-outcome
    update-run-lifecycle
    utc-now
]
use ../../lib/services/context.nu [setup-run-context]
use ../../lib/services/compose-files.nu [build-f-args write-active-files]
use ../../lib/services/lifecycle.nu [
    cleanup-temp
    cleanup-down
    overwrite-cleanup-failed
]
use ../../lib/publish/envelope.nu [publish-envelope-safe]

def main [
    --scenario: string,
    --sender-platform: string,
    --sender-version: string,
    --receiver-platform: string = "",
    --receiver-version: string = "",
    --browser: string = "chrome",
    --no-video,
    --preserve-temp,
    --suite-id: string = "",
    --suite-kind: string = "single",
] {
    let ctx = (setup-run-context
        $scenario $sender_platform $sender_version $browser (not $no_video)
        $receiver_platform $receiver_version
        --suite-id $suite_id --suite-kind $suite_kind)
    let env_file = $ctx.env_file
    let env_args = if ($env_file | is-empty) { [] } else { ["--env-file" $env_file] }
    let base_files = ([$ctx.base_yml] | append (
        $ctx.base_overlay_fnames | each {|f| $ctx.compose_d | path join $f}
    ))
    let f_args_base = (build-f-args $base_files)

    try {
        (validate-compose-strict $base_files $ctx.stack_id
            ($ctx.artifacts_base | path join "compose" "compose.resolved.yml")
            $env_file)
    } catch {|e|
        let finished_at = (utc-now)
        (write-terminal-outcome $ctx.artifacts_base $ctx.execution_id
            $ctx.cell.cell_id $ctx.cell.artifact_name
            $ctx.started_at $finished_at "infra-failed" 1 $ctx.stack_id
            $ctx.images --phase "compose-validate-base" --fail-error $e.msg
            --suite-id $ctx.suite_id --suite-kind $ctx.suite_kind)
        publish-envelope-safe $ctx.artifacts_base
        cleanup-temp $ctx.execution_id $preserve_temp
        error make {msg: $"Compose validation failed: ($e.msg)"}
    }
    let wait_services = if $ctx.is_two_party { ["sender" "receiver" "mitm"] } else { ["sender"] }
    try {
        ^docker compose ...$env_args ...$f_args_base -p $ctx.stack_id up -d --wait ...$wait_services
    } catch {|e|
        let finished_at = (utc-now)
        let up_exit = ($env.LAST_EXIT_CODE? | default 1)
        (write-terminal-outcome $ctx.artifacts_base $ctx.execution_id
            $ctx.cell.cell_id $ctx.cell.artifact_name
            $ctx.started_at $finished_at "infra-failed" $up_exit $ctx.stack_id
            $ctx.images --phase "platform-up" --fail-error $e.msg
            --suite-id $ctx.suite_id --suite-kind $ctx.suite_kind)
        let down_fail = (try { cleanup-down $base_files $ctx.stack_id $ctx.artifacts_base $env_file; null } catch {|ce| $ce.msg})
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
            ($ctx.artifacts_base | path join "compose" "compose.resolved.dev.yml")
            $env_file)
    } catch {|e|
        let finished_at = (utc-now)
        (write-terminal-outcome $ctx.artifacts_base $ctx.execution_id
            $ctx.cell.cell_id $ctx.cell.artifact_name
            $ctx.started_at $finished_at "infra-failed" 1 $ctx.stack_id
            $ctx.images --phase "compose-validate-dev" --fail-error $e.msg
            --suite-id $ctx.suite_id --suite-kind $ctx.suite_kind)
        let down_fail = (try { cleanup-down $base_files $ctx.stack_id $ctx.artifacts_base $env_file; null } catch {|ce| $ce.msg})
        if $down_fail != null {
            overwrite-cleanup-failed $ctx $preserve_temp $down_fail $"dev validation failed: ($e.msg)"
        }
        publish-envelope-safe $ctx.artifacts_base
        cleanup-temp $ctx.execution_id $preserve_temp
        error make {msg: $"Compose dev validation failed: ($e.msg)"}
    }
    write-active-files $ctx.artifacts_base $ctx.base_yml $ctx.base_overlay_fnames "runner-dev.yml"
    try {
        ^docker compose ...$env_args ...$f_args_dev -p $ctx.stack_id up -d cypress_dev
    } catch {|e|
        let finished_at = (utc-now)
        let up_exit = ($env.LAST_EXIT_CODE? | default 1)
        (write-terminal-outcome $ctx.artifacts_base $ctx.execution_id
            $ctx.cell.cell_id $ctx.cell.artifact_name
            $ctx.started_at $finished_at "infra-failed" $up_exit $ctx.stack_id
            $ctx.images --phase "cypress-dev-up" --fail-error $e.msg
            --suite-id $ctx.suite_id --suite-kind $ctx.suite_kind)
        let down_fail = (try { cleanup-down $dev_files $ctx.stack_id $ctx.artifacts_base $env_file; null } catch {|ce| $ce.msg})
        if $down_fail != null {
            overwrite-cleanup-failed $ctx $preserve_temp $down_fail $"cypress_dev up failed: ($e.msg)"
        }
        publish-envelope-safe $ctx.artifacts_base
        cleanup-temp $ctx.execution_id $preserve_temp
        error make {msg: $"Failed to start cypress_dev: ($e.msg)"}
    }

    let port_result = (try {
        ^docker compose ...$env_args ...$f_args_dev -p $ctx.stack_id port cypress_dev 6901 | complete
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
        (write-terminal-outcome $ctx.artifacts_base $ctx.execution_id
            $ctx.cell.cell_id $ctx.cell.artifact_name
            $ctx.started_at $finished_at "infra-failed" 1 $ctx.stack_id
            $ctx.images --phase "cypress-dev-up" --fail-error $port_err
            --suite-id $ctx.suite_id --suite-kind $ctx.suite_kind)
        let down_fail = (try { cleanup-down $dev_files $ctx.stack_id $ctx.artifacts_base $env_file; null } catch {|ce| $ce.msg})
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
        (write-terminal-outcome $ctx.artifacts_base $ctx.execution_id
            $ctx.cell.cell_id $ctx.cell.artifact_name
            $ctx.started_at $finished_at "infra-failed" 1 $ctx.stack_id
            $ctx.images --phase "cypress-dev-up" --fail-error $port_err
            --suite-id $ctx.suite_id --suite-kind $ctx.suite_kind)
        let down_fail = (try { cleanup-down $dev_files $ctx.stack_id $ctx.artifacts_base $env_file; null } catch {|ce| $ce.msg})
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
