# Reusable test fixtures. Most suites need a temp directory with
# guaranteed cleanup; `with-tmp-dir` runs the closure with the temp
# path and removes it afterwards even on error.

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

# Write the 10 canonical source stub files under tmp_root so provenance tests
# can hash real files without needing the actual repo config tree.
# All stubs satisfy the shape contract required by build-matrix-rules-json.
export def materialize-provenance-stubs [tmp_root: string]: nothing -> nothing {
    mkdir ($tmp_root | path join "config/matrix/flows")
    mkdir ($tmp_root | path join "config/adapters")

    ({browsers_default: ["chrome"]} | to nuon)
    | save --force ($tmp_root | path join "config/matrix/defaults.nuon")

    ({
        schema_version: 1
        platforms: {
            nextcloud:  {slug: "nc",        display_name: "Nextcloud",             version_lines: ["v34"]}
            ocmgo:      {slug: "ocmgo",     display_name: "Open Cloud Mesh Golang", version_lines: ["v1"]}
            ocis:       {slug: "ocis",      display_name: "oCIS",                  version_lines: ["v8"]}
            opencloud:  {slug: "opencloud", display_name: "OpenCloud",             version_lines: ["v6"]}
        }
    } | to nuon)
    | save --force ($tmp_root | path join "config/matrix/platforms.nuon")

    ({
        baseline_by_flow: {
            login:            {sender: "nextcloud", receiver: null}
            "share-with":     {sender: "nextcloud", receiver: "nextcloud"}
            "contact-token":  {sender: "nextcloud", receiver: "nextcloud"}
            "contact-wayf":   {sender: "nextcloud", receiver: "nextcloud"}
            "code-flow":      {sender: "nextcloud", receiver: "nextcloud"}
        }
        overrides: {}
    } | to nuon)
    | save --force ($tmp_root | path join "config/matrix/naming.nuon")

    "{}" | save --force ($tmp_root | path join "config/matrix/capabilities.v1.nuon")

    let flows = [
        {stem: "code-flow",     label: "Code Flow",         subtitle: "Code flow",       order: 50, two_party: true,  mitm: true}
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
