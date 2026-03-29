# Matrix domain: test matrix management.

use ../../lib/cell.nu [compute-cell validate-cell-rules]
use ../../lib/images.nu [resolve-images resolve-receiver-image resolve-mitmproxy-image]
use ../../lib/actors.nu [validate-actor-config]
use ../../lib/domain/core/ocmts-root.nu [get-ocmts-root]

def main [] {
    print "Usage: nu scripts/ocmts.nu matrix <verb> [flags]"
    print ""
    print "Verbs:"
    print "  list   List all matrix cells from config/matrix-rules.nuon"
    print "  cell   Compute cell_id and image refs for a matrix entry"
}

# List all matrix cells defined in config/matrix-rules.nuon.
def "main list" [--json] {
    let root = get-ocmts-root
    let rules = open ($root | path join "config/matrix-rules.nuon")
    let cells = ($rules.scenarios | items {|scenario, sc|
        $sc.sender.version_lines | each {|ver|
            $sc.browsers | each {|browser|
                {
                    scenario: $scenario,
                    sender_platform: $sc.sender.platform,
                    sender_version: $ver,
                    receiver_platform: ($sc.receiver?.platform? | default ""),
                    receiver_version: (if $sc.receiver? != null {
                        ($sc.receiver.version_lines | first)
                    } else { "" }),
                    mitm: ($sc.mitm? | default false),
                    browser: $browser,
                }
            }
        } | flatten
    } | flatten)
    if $json {
        $cells | to json
    } else {
        $cells | table
    }
}

def "main cell" [
    --scenario: string,                   # Test scenario name (e.g. login, share-with)
    --sender-platform: string,            # Sender platform (e.g. nextcloud)
    --sender-version: string,             # Sender platform version (e.g. v33)
    --receiver-platform: string = "",     # Receiver platform (required for two-party scenarios)
    --receiver-version: string = "",      # Receiver platform version (required for two-party scenarios)
    --browser: string = "chrome",         # Browser
    --json,                               # Output as JSON
] {
    let root = get-ocmts-root
    (validate-cell-rules
        $scenario $sender_platform $sender_version $browser
        $receiver_platform $receiver_version)
    (validate-actor-config $scenario $root $sender_platform $receiver_platform)
    let cell = (compute-cell
        $scenario $sender_platform $sender_version $browser
        $receiver_platform $receiver_version)
    let images = (resolve-images $sender_platform $sender_version)
    mut result = ($cell | insert images $images)
    if $cell.is_two_party {
        let recv_img = (resolve-receiver-image $receiver_platform $receiver_version)
        let mitm_img = (resolve-mitmproxy-image)
        $result = ($result | insert receiver_image $recv_img | insert mitmproxy_image $mitm_img)
    }
    if $json {
        $result | to json
    } else {
        print $"cell_id:           ($result.cell_id)"
        print $"artifact_name:     ($result.artifact_name)"
        print $"browser:           ($result.browser)"
        print $"is_two_party:      ($result.is_two_party)"
        print $"images.platform:   ($result.images.platform)"
        print $"images.cypress_ci: ($result.images.cypress_ci)"
        if $cell.is_two_party {
            print $"receiver_image:    ($result.receiver_image)"
            print $"mitmproxy_image:   ($result.mitmproxy_image)"
        }
    }
}
