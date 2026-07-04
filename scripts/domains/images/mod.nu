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
    print "  show              Show raw version-scoped config for one platform/version"
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
    let has_role_env = ("sender_override_env" in ($spec | columns)) or ("receiver_override_env" in ($spec | columns))

    print $"platform:      ($platform)"
    print $"version:       ($version)"
    print $"default:       ($spec.default)"
    print $"override_env:  ($spec.override_env? | default "")"

    if $has_role_env {
        print $"sender_override_env:   ($spec.sender_override_env? | default "")"
        print $"receiver_override_env: ($spec.receiver_override_env? | default "")"
    }

    let bundle = ($spec.bundle? | default {})
    if not ($bundle | is-empty) {
        print "bundle:"
        for slot in ($bundle | columns) {
            let slot_spec = ($bundle | get $slot)
            print $"  ($slot): default=($slot_spec.default) override_env=($slot_spec.override_env? | default "")"
        }
    }

    print ""
    print "note: this is the raw version-scoped config; by_matrix_key/by_flow overrides are not applied here"
    print "note: use 'images resolve --flow ...' for full effective resolution"
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
