# Reusable test fixtures.

export def make-cell [overrides?: record]: nothing -> record {
    let defaults = {
        cell_id: "login__nextcloud-v34",
        artifact_name: "cell-login-nextcloud-v34",
        matrix_key: "login__nextcloud",
        flow_id: "login",
        sender_platform: "nextcloud",
        sender_version: "v34",
        receiver_platform: "",
        receiver_version: "",
        is_two_party: false,
        execution_id: "20260101t000000-aaaaaaaa",
        capabilities_produced: [],
        capability_action: "run",
        depends_on: [],
    }
    if $overrides != null {
        $defaults | merge $overrides
    } else {
        $defaults
    }
}

export def with-tmp-dir [closure: closure]: nothing -> any {
    let tmp = (^mktemp -d | str trim)
    try {
        let result = (do $closure $tmp)
        ^rm -rf $tmp
        $result
    } catch {|err|
        ^rm -rf $tmp
        error make {msg: $err.msg}
    }
}

# Write the 8 canonical source stub files under tmp_root for provenance tests.
export def materialize-provenance-stubs [tmp_root: string]: nothing -> nothing {
    mkdir ($tmp_root | path join "config/matrix/flows")
    mkdir ($tmp_root | path join "config/adapters")

    ({browsers_default: ["chrome"]} | to nuon)
    | save --force ($tmp_root | path join "config/matrix/defaults.nuon")

    ({
        schema_version: 1
        platforms: {
            nextcloud:  {display_name: "Nextcloud",             version_lines: ["v34"]}
            ocmgo:      {display_name: "OpenCloudMesh Go", version_lines: ["v1"]}
            ocis:       {display_name: "oCIS",                  version_lines: ["v8"]}
            opencloud:  {display_name: "OpenCloud",             version_lines: ["v6"]}
        }
    } | to nuon)
    | save --force ($tmp_root | path join "config/matrix/platforms.nuon")

    "{}" | save --force ($tmp_root | path join "config/matrix/capabilities.v1.nuon")

    let flows = [
        {stem: "contact-token", label: "Contact via Token", subtitle: "Token discovery", order: 30, two_party: true,  mitm: true}
        {stem: "contact-wayf",  label: "Contact via WAYF",  subtitle: "WAYF discovery",  order: 40, two_party: true,  mitm: true}
        {stem: "login",         label: "Login Flow",        subtitle: "Login flow",      order: 10, two_party: false, mitm: false}
        {stem: "share-with",    label: "Share With",        subtitle: "Share-with flow", order: 20, two_party: true,  mitm: true}
    ]
    for s in $flows {
        ({
            flow_id:               $s.stem
            label:                 $s.label
            subtitle:              $s.subtitle
            display_order:         $s.order
            enabled:               false
            two_party:             $s.two_party
            mitm:                  $s.mitm
            required_capabilities: {sender: [], receiver: []}
        } | to nuon)
        | save --force ($tmp_root | path join "config/matrix/flows" $"($s.stem).nuon")
    }

    "{}" | save --force ($tmp_root | path join "config/adapters/capabilities.v1.nuon")
}
