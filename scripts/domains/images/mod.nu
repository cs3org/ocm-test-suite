# Images domain: container image configuration queries.

use ../../lib/images/config.nu [list-platforms-versions validate-platform-version]
use ../../lib/images/resolve.nu [resolve-images resolve-receiver-image resolve-mitmproxy-image]
use ../../lib/domain/core/ocmts-root.nu [get-ocmts-root]
use ../../lib/matrix/rules-gen.nu [load-matrix-rules]

def main [] {
    print "Usage: nu scripts/ocmts.nu images <verb> [flags]"
    print ""
    print "Verbs:"
    print "  list              List all configured platforms and versions"
    print "  show              Show raw/base image config for one platform/version (no scenario overrides)"
    print "  resolve           Resolve effective image refs with scenario/flow overrides applied"
}

# List all configured platforms and versions from config/images.nuon.
def "main list" [--json] {
    let rows = list-platforms-versions
    if $json {
        $rows | to json
    } else {
        $rows | table
    }
}

# Show raw/base image config for one platform/version.
# Only base default and override_env fields are shown; by_scenario and
# by_flow overrides are NOT applied. For the effective image refs that a
# real test run would use, see: images resolve --scenario <name> ...
def "main show" [
    --platform: string,  # Sender platform (e.g. nextcloud)
    --version: string,   # Platform version (e.g. v33)
] {
    validate-platform-version $platform $version
    let root = get-ocmts-root
    let imgs = open ($root | path join "config/images.nuon")
    let plat_spec = ($imgs.platforms | get $platform)
    let spec = ($plat_spec | get $version)
    let platform_env = ($plat_spec.override_env? | default "")
    let version_env = ($spec.override_env? | default "")
    let effective_env = if not ($version_env | is-empty) { $version_env } else { $platform_env }
    let env_val = if ($effective_env | is-empty) {
        ""
    } else {
        ($env | get --optional $effective_env | default "")
    }
    let base_image = if ($env_val | is-empty) { $spec.default } else { $env_val }
    print $"platform:               ($platform)"
    print $"version:                ($version)"
    print $"default:                ($spec.default)"
    print $"platform_override_env:  ($platform_env)"
    print $"version_override_env:   ($version_env)"
    print $"effective_override_env: ($effective_env)"
    print $"base_image:             ($base_image)"
    if not ($env_val | is-empty) {
        print $"note: ($effective_env) is set; using env override"
    }
    print "note: by_scenario/by_flow overrides not applied; use 'images resolve --scenario' for full resolution"
}

# Resolve image refs for a scenario and sender platform/version.
# Pass --receiver-platform and --receiver-version for two-party scenarios.
# Pass --scenario to enable by_flow/by_scenario image precedence.
def "main resolve" [
    --scenario: string = "",          # Scenario name (enables by_flow lookup)
    --sender-platform: string,        # Sender platform (e.g. nextcloud)
    --sender-version: string,         # Platform version (e.g. v33)
    --receiver-platform: string = "", # Receiver platform (for two-party scenarios)
    --receiver-version: string = "",  # Receiver version (for two-party scenarios)
    --json,
] {
    # Derive flow_id from matrix-rules when scenario is provided.
    let flow_id = if (not ($scenario | is-empty)) {
        let root = get-ocmts-root
        let rules = (load-matrix-rules $root)
        let sc = ($rules.scenarios | get --optional $scenario | default null)
        if $sc != null {
            $sc.flow_id? | default $scenario
        } else {
            $scenario
        }
    } else { "" }

    let sender_result = (resolve-images $sender_platform $sender_version
        --scenario $scenario --flow-id $flow_id)
    mut output = $sender_result

    if (not ($receiver_platform | is-empty)) {
        let recv_img = (resolve-receiver-image $receiver_platform $receiver_version
            --scenario $scenario --flow-id $flow_id)
        let mitm_img = (resolve-mitmproxy-image --scenario $scenario --flow-id $flow_id)
        $output = ($output | insert receiver_platform $recv_img | insert mitmproxy $mitm_img)
    }

    if $json {
        $output | to json
    } else {
        print $"sender_platform: ($output.platform)"
        if (not ($receiver_platform | is-empty)) {
            print $"receiver_platform: ($output.receiver_platform)"
            print $"mitmproxy:         ($output.mitmproxy)"
        }
        print $"cypress_ci:      ($output.cypress_ci)"
        print $"cypress_dev:     ($output.cypress_dev)"
        print $"mariadb:         ($output.mariadb)"
        print $"valkey:          ($output.valkey)"
    }
}
