# Images domain: container image configuration queries.

use ../../lib/domain/core/ocmts-root.nu [get-ocmts-root]
use ../../lib/images/config.nu [list-platforms-versions validate-platform-version]
use ../../lib/images/resolve.nu [resolve-images resolve-receiver-image resolve-mitmproxy-image]
use ../../lib/matrix/cell.nu [assert-matrix-entry-enabled compute-cell validate-cell-rules]
use ../../lib/matrix/rules-gen.nu [load-matrix-rules matrix-key]

def main [] {
    print "Usage: nu scripts/ocmts.nu images <verb> [flags]"
    print ""
    print "Verbs:"
    print "  list              List all configured platforms and versions"
    print "  show              Show raw/base image config for one platform/version"
    print "  resolve           Resolve effective image refs with matrix/flow overrides"
}

def "main list" [--json] {
    let rows = list-platforms-versions
    if $json {
        $rows | to json
    } else {
        $rows | table
    }
}

def "main show" [
    --platform: string,
    --version: string,
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
    print "note: by_matrix_key/by_flow overrides not applied; use 'images resolve --flow' for full resolution"
}

def "main resolve" [
    --flow: string,
    --sender-platform: string,
    --sender-version: string,
    --receiver-platform: string = "",
    --receiver-version: string = "",
    --json,
] {
    let root = get-ocmts-root
    assert-matrix-entry-enabled $flow $sender_platform $receiver_platform
    let mk = (matrix-key $flow $sender_platform $receiver_platform)
    let rules = (load-matrix-rules $root)
    let browser = ($rules.matrix | get $mk | get browsers | first)
    validate-cell-rules $flow $sender_platform $sender_version $browser $receiver_platform $receiver_version
    let cell = (compute-cell $flow $sender_platform $sender_version $browser $receiver_platform $receiver_version)
    let flow_id = $cell.flow_id

    let sender_result = (resolve-images $sender_platform $sender_version
        --matrix-key $cell.matrix_key --flow-id $flow_id)
    mut output = $sender_result

    if $cell.is_two_party {
        let recv_img = (resolve-receiver-image $receiver_platform $receiver_version
            --matrix-key $cell.matrix_key --flow-id $flow_id)
        let mitm_img = (resolve-mitmproxy-image --matrix-key $cell.matrix_key --flow-id $flow_id)
        $output = ($output | insert receiver_platform $recv_img | insert mitmproxy $mitm_img)
    }

    if $json {
        $output | to json
    } else {
        print $"sender_platform: ($output.platform)"
        if $cell.is_two_party {
            print $"receiver_platform: ($output.receiver_platform)"
            print $"mitmproxy:         ($output.mitmproxy)"
        }
        print $"cypress_ci:      ($output.cypress_ci)"
        print $"cypress_dev:     ($output.cypress_dev)"
        print $"mariadb:         ($output.mariadb)"
        print $"valkey:          ($output.valkey)"
    }
}
