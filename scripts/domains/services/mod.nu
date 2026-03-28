# Services domain: docker compose lifecycle management.

use ../../lib/cell.nu [compute-cell validate-cell-rules]
use ../../lib/images.nu [resolve-images]
use ../../lib/execution-id.nu [new-execution-id execution-artifacts-path execution-temp-path]
use ../../lib/actors.nu [validate-actor-config]
use ../../lib/compose-render.nu [write-compose-overlays]
use ../../lib/compose-validate.nu [validate-compose-strict]
use ../../lib/run-metadata.nu [
    write-prepared-run
    write-terminal-run
    write-compact-result
    update-run-lifecycle
    utc-now
]
use ../../lib/artifacts-init.nu [
    init-artifact-dirs
    write-last-execution-id
    read-last-execution-id
]
use ../../lib/domain/core/ocmts-root.nu [get-ocmts-root]
use ../../lib/docker-logs.nu [collect-service-logs]

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

# Build the list of -f args for docker compose from an ordered list of files.
def build-f-args [files: list<string>] {
    $files | each {|f| ["-f" $f]} | flatten
}

# Remove /tmp/ocmts/<execution_id> when not preserving temp.
# Uses execution-temp-path which validates the id before any rm.
# Best-effort: warns on rm failure so downstream metadata writes are never skipped.
def cleanup-temp [execution_id: string, preserve_temp: bool] {
    if $preserve_temp { return }
    if ($execution_id | is-empty) { return }
    let tmp_d = (execution-temp-path $execution_id)
    try {
        if ($tmp_d | path exists) { rm -rf $tmp_d }
    } catch {|e|
        print $"WARNING: temp cleanup failed for ($tmp_d): ($e.msg)"
    }
}

# After compose down, verify the project network (named by stack_id) is gone.
# Compose down can return exit 0 while the network lingers briefly. Attempts
# removal once; if that fails, waits 2s and retries once more. Throws if the
# network still exists after both attempts so callers surface a truthful error.
def ensure-network-gone [stack_id: string] {
    let inspect = (try {
        ^docker network inspect $stack_id | complete
    } catch {
        {exit_code: 1, stdout: "", stderr: ""}
    })
    if $inspect.exit_code != 0 { return }

    print $"WARNING: network ($stack_id) still present after compose down; removing..."
    let rm1 = (try {
        ^docker network rm $stack_id | complete
    } catch {
        {exit_code: 1, stdout: "", stderr: ""}
    })
    if $rm1.exit_code == 0 { return }

    # First attempt failed - wait briefly for any lingering container detach, then retry.
    sleep 2sec
    let rm2 = (try {
        ^docker network rm $stack_id | complete
    } catch {
        {exit_code: 1, stdout: "", stderr: ""}
    })
    if $rm2.exit_code != 0 {
        let err = ($rm2.stderr | str trim)
        error make {msg: $"network ($stack_id) still present after compose down; removal failed: ($err)"}
    }
}

# Validate down file set then run compose down.
# Throws on validation failure (skips compose down) or on compose down failure.
# Callers must wrap in try/catch, run cleanup-temp, and surface the error.
def cleanup-down [
    files: list<string>,
    stack_id: string,
    artifacts_base: string = "",
] {
    let resolved_path = if ($artifacts_base | is-empty) {
        ""
    } else {
        $artifacts_base | path join "compose" "compose.resolved.down.yml"
    }
    validate-compose-strict $files $stack_id $resolved_path
    let f_args = (build-f-args $files)
    ^docker compose ...$f_args -p $stack_id down --volumes
    ensure-network-gone $stack_id
}

# Overwrite run/result metadata to cleanup-failed when a down attempt fails
# after an earlier failure. Always throws with the combined error message.
def overwrite-cleanup-failed [
    ctx: record,
    preserve_temp: bool,
    down_fail: string,
    original_err: string,
] {
    let cf_at = (utc-now)
    let combined = $"cleanup/down failed: ($down_fail) [($original_err)]"
    (write-terminal-run $ctx.artifacts_base $ctx.execution_id
        $ctx.cell.cell_id $ctx.cell.artifact_name
        $ctx.started_at $cf_at "cleanup-failed" 1 $ctx.stack_id
        $ctx.images --phase "compose-down" --fail-error $combined)
    (write-compact-result $ctx.artifacts_base $ctx.execution_id
        $ctx.cell.cell_id "cleanup-failed" 1 $cf_at)
    cleanup-temp $ctx.execution_id $preserve_temp
    error make {msg: $combined}
}

# Persist the exact active compose file set to compose/active-files.txt.
# Uses artifact input paths so the file survives /tmp cleanup.
def write-active-files [
    artifacts_base: string,
    base_yml: string,
    runner_fname: string = "",
] {
    let art_inputs = ($artifacts_base | path join "compose" "inputs")
    let base_files = [
        $base_yml
        ($art_inputs | path join "exec.yml")
        ($art_inputs | path join "platform.yml")
        ($art_inputs | path join "helpers.yml")
    ]
    let active_files = if ($runner_fname | is-empty) {
        $base_files
    } else {
        $base_files | append ($art_inputs | path join $runner_fname)
    }
    $active_files | str join "\n"
    | save --force ($artifacts_base | path join "compose" "active-files.txt")
}

# Shared setup: compute IDs, create dirs, generate overlays, write initial meta.
def setup-run-context [
    scenario: string,
    sender_platform: string,
    sender_version: string,
    browser: string,
    record_video: bool,
] {
    let root = get-ocmts-root
    validate-cell-rules $scenario $sender_platform $sender_version $browser
    validate-actor-config $scenario $root $sender_platform
    let cell = (compute-cell $scenario $sender_platform $sender_version $browser)
    let images = (resolve-images $sender_platform $sender_version)
    let execution_id = (new-execution-id)
    let artifacts_base = (init-artifact-dirs $cell.artifact_name $execution_id)

    let spec_entrypoint = $"cypress/e2e/($scenario)/index.cy.ts"
    let overlay = (write-compose-overlays
        $scenario $sender_platform
        $cell.artifact_name $execution_id
        $images.platform $images.cypress_ci $images.cypress_dev
        $images.mariadb $images.valkey
        $spec_entrypoint $browser $record_video
        $root $artifacts_base
    )

    let started_at = (utc-now)

    ($cell | insert execution_id $execution_id | insert images $images)
        | to json
        | save --force ($artifacts_base | path join "meta/cell.json")

    (write-prepared-run
        $artifacts_base $execution_id $cell.cell_id
        $cell.artifact_name $started_at $overlay.stack_id)

    # Publish latest only after prepared metadata is durable.
    write-last-execution-id $cell.artifact_name $execution_id

    {
        cell: $cell,
        images: $images,
        execution_id: $execution_id,
        artifacts_base: $artifacts_base,
        started_at: $started_at,
        stack_id: $overlay.stack_id,
        compose_d: $overlay.compose_d,
        base_yml: $overlay.base_yml,
    }
}

def "main up" [
    --scenario: string,
    --sender-platform: string,
    --sender-version: string,
    --browser: string = "chrome",
    --record,
    --preserve-temp,
] {
    let ctx = (setup-run-context $scenario $sender_platform $sender_version $browser $record)
    let base_files = [
        $ctx.base_yml
        ($ctx.compose_d | path join "exec.yml")
        ($ctx.compose_d | path join "platform.yml")
        ($ctx.compose_d | path join "helpers.yml")
    ]
    let f_args = (build-f-args $base_files)
    write-active-files $ctx.artifacts_base $ctx.base_yml
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
        cleanup-temp $ctx.execution_id $preserve_temp
        error make {msg: $"Compose validation failed: ($e.msg)"}
    }
    # --wait blocks until platform (and its helper deps) reach healthy/started.
    try {
        ^docker compose ...$f_args -p $ctx.stack_id up -d --wait platform
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
    --browser: string = "chrome",
    --record,
    --preserve-temp,
    --keep-up,
] {
    let ctx = (setup-run-context $scenario $sender_platform $sender_version $browser $record)
    let base_files = [
        $ctx.base_yml
        ($ctx.compose_d | path join "exec.yml")
        ($ctx.compose_d | path join "platform.yml")
        ($ctx.compose_d | path join "helpers.yml")
    ]
    let f_args_base = (build-f-args $base_files)
    let run_files = ($base_files | append ($ctx.compose_d | path join "runner-ci.yml"))
    let f_args_run = (build-f-args $run_files)
    # Write base-only active files first; updated to runner-ci only after it validates.
    write-active-files $ctx.artifacts_base $ctx.base_yml

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
        cleanup-temp $ctx.execution_id $preserve_temp
        error make {msg: $"Compose base validation failed: ($e.msg)"}
    }

    # Bring up platform and helpers; --wait blocks until healthy/started.
    try {
        ^docker compose ...$f_args_base -p $ctx.stack_id up -d --wait platform
    } catch {|e|
        let finished_at = (utc-now)
        let up_exit = ($env.LAST_EXIT_CODE? | default 1)
        (write-terminal-run $ctx.artifacts_base $ctx.execution_id
            $ctx.cell.cell_id $ctx.cell.artifact_name
            $ctx.started_at $finished_at "infra-failed" $up_exit $ctx.stack_id
            $ctx.images --phase "platform-up" --fail-error $e.msg)
        (write-compact-result $ctx.artifacts_base $ctx.execution_id
            $ctx.cell.cell_id "infra-failed" $up_exit $finished_at)
        if not $keep_up {
            let down_fail = (try { cleanup-down $base_files $ctx.stack_id $ctx.artifacts_base; null } catch {|ce| $ce.msg})
            if $down_fail != null {
                overwrite-cleanup-failed $ctx $preserve_temp $down_fail $"platform-up failed: ($e.msg)"
            }
        }
        cleanup-temp $ctx.execution_id $preserve_temp
        error make {msg: $"docker compose up platform failed: ($e.msg)"}
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
        cleanup-temp $ctx.execution_id $preserve_temp
        error make {msg: $"Compose runner-ci validation failed: ($e.msg)"}
    }
    # runner-ci validated: now the runner overlay is about to be active.
    write-active-files $ctx.artifacts_base $ctx.base_yml "runner-ci.yml"

    print $"Running tests for ($ctx.cell.cell_id) [execution_id=($ctx.execution_id)]..."
    # Wrap docker compose run with bash+tee to capture stdout+stderr while
    # preserving the Cypress exit code exactly via ${PIPESTATUS[0]}.
    let logs_dir = ($ctx.artifacts_base | path join "docker" "logs")
    if not ($logs_dir | path exists) {
        try { mkdir $logs_dir } catch {|e| print $"WARNING: could not create log dir: ($e.msg)" }
    }
    let cypress_log = ($logs_dir | path join "cypress-run.log")
    let tee_script = 'set -o pipefail; log="$1"; shift; "$@" 2>&1 | tee "$log"; exit ${PIPESTATUS[0]}'
    try {
        ^bash -c $tee_script -- $cypress_log docker compose ...$f_args_run -p $ctx.stack_id run --rm cypress
    } catch { }
    let cypress_exit = $env.LAST_EXIT_CODE
    let cypress_status = if $cypress_exit == 0 { "passed" } else { "failed" }

    # Verify cypress log was written; warn if missing or empty.
    # Best-effort: must not throw or change exit code.
    try {
        let log_missing_or_empty = if not ($cypress_log | path exists) {
            true
        } else {
            let log_size = (ls $cypress_log | first | get size)
            $log_size == 0b
        }
        if $log_missing_or_empty {
            let warn_msg = $"WARNING: cypress-run.log missing or empty: ($cypress_log)"
            print $warn_msg
            try { mkdir ($ctx.artifacts_base | path join "meta") } catch { }
            try {
                $warn_msg | save --force ($ctx.artifacts_base | path join "meta/cypress-run-warning.txt")
            } catch {|se| print $"WARNING: could not write cypress-run-warning.txt: ($se.msg)" }
        }
    } catch {|e|
        print $"WARNING: could not check cypress-run.log: ($e.msg)"
    }

    # Collect platform service logs before tearing down while the stack is still up.
    # Best-effort: any failure becomes a WARNING; does not affect teardown or exit code.
    try {
        let log_result = (collect-service-logs $ctx.artifacts_base $ctx.stack_id $run_files
            ["platform" "platform-db" "platform-cache"])
        if not $log_result.ok {
            let failed_svcs = (
                $log_result.services
                | where {|s| not $s.ok}
                | each {|s| $s.service}
                | str join ", "
            )
            print $"WARNING: docker log collection failed for services: ($failed_svcs)"
            let warn_lines = (
                $log_result.services
                | where {|s| not $s.ok}
                | each {|s| $"($s.service): ($s.error? | default 'unknown')"}
                | str join "\n"
            )
            try {
                $warn_lines | save --force ($ctx.artifacts_base | path join "meta/docker-log-warning.txt")
            } catch {|se| print $"WARNING: could not write docker-log-warning.txt: ($se.msg)" }
        }
    } catch {|e|
        print $"WARNING: docker log collection threw an error: ($e.msg)"
    }

    mut down_err = null
    if not $keep_up {
        print "Tearing down services..."
        let art_inputs = ($ctx.artifacts_base | path join "compose" "inputs")
        # Use only the files that were active during this run (no runner-dev).
        let down_files = [
            $ctx.base_yml
            ($art_inputs | path join "exec.yml")
            ($art_inputs | path join "platform.yml")
            ($art_inputs | path join "helpers.yml")
            ($art_inputs | path join "runner-ci.yml")
        ]
        let f_args_down = (build-f-args $down_files)
        # Validate before down; if it fails, skip compose down and record the error.
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
            try {
                ^docker compose ...$f_args_down -p $ctx.stack_id down --volumes
                ensure-network-gone $ctx.stack_id
                null
            } catch {|e|
                $e.msg
            }
        }
    }

    # Write metadata before cleanup so rm failure cannot skip the final record.
    let finished_at = (utc-now)
    if $down_err != null {
        # Teardown failed: record cleanup failure, preserve Cypress outcome in error field.
        let down_fail_msg = $"cleanup/down failed: ($down_err)"
        (write-terminal-run $ctx.artifacts_base $ctx.execution_id
            $ctx.cell.cell_id $ctx.cell.artifact_name
            $ctx.started_at $finished_at "cleanup-failed" 1 $ctx.stack_id
            $ctx.images --phase "compose-down"
            --fail-error $"($down_fail_msg) [cypress: status=($cypress_status) exit=($cypress_exit)]")
        (write-compact-result $ctx.artifacts_base $ctx.execution_id
            $ctx.cell.cell_id "cleanup-failed" 1 $finished_at)
        cleanup-temp $ctx.execution_id $preserve_temp
        error make {msg: $down_fail_msg}
    }

    (write-terminal-run $ctx.artifacts_base $ctx.execution_id
        $ctx.cell.cell_id $ctx.cell.artifact_name
        $ctx.started_at $finished_at $cypress_status $cypress_exit $ctx.stack_id
        $ctx.images)
    (write-compact-result $ctx.artifacts_base $ctx.execution_id
        $ctx.cell.cell_id $cypress_status $cypress_exit $finished_at)
    cleanup-temp $ctx.execution_id $preserve_temp
    print $"Done. status=($cypress_status) execution_id=($ctx.execution_id)"
    print $"Artifacts: ($ctx.artifacts_base)"
    exit $cypress_exit
}

def "main up open" [
    --scenario: string,
    --sender-platform: string,
    --sender-version: string,
    --browser: string = "chrome",
    --preserve-temp,
] {
    let ctx = (setup-run-context $scenario $sender_platform $sender_version $browser false)
    let base_files = [
        $ctx.base_yml
        ($ctx.compose_d | path join "exec.yml")
        ($ctx.compose_d | path join "platform.yml")
        ($ctx.compose_d | path join "helpers.yml")
    ]
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
        cleanup-temp $ctx.execution_id $preserve_temp
        error make {msg: $"Compose validation failed: ($e.msg)"}
    }
    # Start platform and its helper dependencies; wait for them to be ready.
    try {
        ^docker compose ...$f_args_base -p $ctx.stack_id up -d --wait platform
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
        cleanup-temp $ctx.execution_id $preserve_temp
        error make {msg: $"Failed to start platform services: ($e.msg)"}
    }
    # Platform is active: record the base-only file set before proceeding.
    write-active-files $ctx.artifacts_base $ctx.base_yml
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
        cleanup-temp $ctx.execution_id $preserve_temp
        error make {msg: $"Compose dev validation failed: ($e.msg)"}
    }
    # runner-dev validated: update active-files before starting cypress_dev.
    write-active-files $ctx.artifacts_base $ctx.base_yml "runner-dev.yml"
    # Start cypress_dev detached; the image runs the Kasm desktop startup.
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
        # Use dev_files so compose resolves all active services for teardown.
        let down_fail = (try { cleanup-down $dev_files $ctx.stack_id $ctx.artifacts_base; null } catch {|ce| $ce.msg})
        if $down_fail != null {
            overwrite-cleanup-failed $ctx $preserve_temp $down_fail $"cypress_dev up failed: ($e.msg)"
        }
        cleanup-temp $ctx.execution_id $preserve_temp
        error make {msg: $"Failed to start cypress_dev: ($e.msg)"}
    }

    # Must include the same -f args used at startup so compose resolves the service.
    # Guarded: a port lookup failure before run.json is marked open would leave stale metadata.
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
    --execution-id: string = "",
    --preserve-temp,
] {
    let root = get-ocmts-root
    let cell = (compute-cell $scenario $sender_platform $sender_version "chrome")
    let exec_id = if ($execution_id | is-empty) {
        read-last-execution-id $cell.artifact_name
    } else {
        $execution_id
    }
    # Validate and construct artifact base path; rejects path traversal.
    let artifacts_base = (execution-artifacts-path $root $cell.artifact_name $exec_id)

    # Read stack_id from artifacts; available even if /tmp is gone.
    let stack_id_file = ($artifacts_base | path join "compose" "stack_id.txt")
    if not ($stack_id_file | path exists) {
        error make {msg: $"No stack_id found for execution_id=($exec_id). Artifacts may be missing."}
    }
    let stack_id = (open --raw $stack_id_file | str trim)

    print $"Tearing down ($cell.cell_id) [stack_id=($stack_id)]..."
    let base_yml = ($root | path join "config/compose/base.yml")
    let art_inputs = ($artifacts_base | path join "compose" "inputs")
    let active_files_path = ($artifacts_base | path join "compose" "active-files.txt")
    let down_files = if ($active_files_path | path exists) {
        open --raw $active_files_path | lines | where {|l| not ($l | is-empty)}
    } else {
        # Conservative base-only fallback; runner overlays may never have been active.
        print "WARNING: active-files.txt not found; using base-only file set (legacy artifacts)"
        [
            $base_yml
            ($art_inputs | path join "exec.yml")
            ($art_inputs | path join "platform.yml")
            ($art_inputs | path join "helpers.yml")
        ]
    }
    let f_args_down = (build-f-args $down_files)
    # Validate before down; if it fails, clean temp then throw without running down.
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

    # Always clean temp before surfacing a down failure.
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
