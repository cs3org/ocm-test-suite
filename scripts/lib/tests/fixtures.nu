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
# Flow stubs include a flow_id and empty required_capabilities so that
# load-flow-caps can parse them without error.
export def materialize-provenance-stubs [tmp_root: string]: nothing -> nothing {
    mkdir ($tmp_root | path join "config/matrix/flows")
    mkdir ($tmp_root | path join "config/adapters")
    for f in ["defaults.nuon" "platforms.nuon" "naming.nuon" "capabilities.v1.nuon"] {
        "{}" | save --force ($tmp_root | path join "config/matrix" $f)
    }
    for stem in ["code-flow" "contact-token" "contact-wayf" "login" "share-with"] {
        ({flow_id: $stem, required_capabilities: {sender: [], receiver: []}} | to nuon)
        | save --force ($tmp_root | path join "config/matrix/flows" $"($stem).nuon")
    }
    "{}" | save --force ($tmp_root | path join "config/adapters/capabilities.v1.nuon")
}
