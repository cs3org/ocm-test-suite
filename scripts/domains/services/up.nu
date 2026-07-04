# Bring up platform+helper services for a cell (no test run).

use ../../lib/compose/validate.nu [validate-compose-strict]
use ../../lib/run/metadata.nu [update-run-lifecycle]
use ../../lib/time/utc.nu [utc-now]
use ../../lib/services/context.nu [setup-run-context]
use ../../lib/services/compose-files.nu [
    build-f-args write-compose-manifest
]
use ../../lib/services/lifecycle.nu [cleanup-temp]
use ../../lib/services/infra-fail.nu [with-infra-fail-cleanup]
use ../../lib/images/cell-images.nu [emit-cell-images]

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
    let f_args = (build-f-args $base_files)
    (write-compose-manifest $ctx.artifacts_base $ctx.stack_id
        $ctx.base_overlay_fnames "" ["compose.resolved.yml"])
    (with-infra-fail-cleanup $ctx "compose-validate-base" {
        (validate-compose-strict $base_files $ctx.stack_id
            ($ctx.artifacts_base | path join "compose" "compose.resolved.yml")
            $env_file)
    } --preserve-temp=$preserve_temp)
    let wait_services = if $ctx.is_two_party { ["sender" "receiver" "mitm"] } else { [] }
    (with-infra-fail-cleanup $ctx "platform-up" {
        # Direct compose up (operator-facing): streams output and throws on failure, caught by with-infra-fail-cleanup. CI flow uses do-compose-up in services/up-run.nu. Empty wait_services splats to full project (no service targets).
        ^docker compose ...$env_args ...$f_args -p $ctx.stack_id up -d --wait ...$wait_services
        emit-cell-images $ctx.artifacts_base $ctx.stack_id $ctx.images $ctx.is_two_party
    } --preserve-temp=$preserve_temp --base-files $base_files --env-file $env_file)
    update-run-lifecycle $ctx.artifacts_base "active" --phase "platform-up"
    print $"Stack up. execution_id=($ctx.execution_id) stack_id=($ctx.stack_id)"
    print $"Artifacts: ($ctx.artifacts_base)"
}
