# Matrix domain: test matrix management.

use ../../lib/matrix/cell.nu [compute-cell validate-cell-rules]
use ../../lib/images/resolve.nu [resolve-images resolve-receiver-image resolve-mitmproxy-image]
use ../../lib/domain/core/ocmts-root.nu [get-ocmts-root]
use ../../lib/matrix/rules-gen.nu [load-matrix-rules]
use ../../lib/matrix/cypress-gen.nu [write-cypress-matrix-files check-cypress-matrix-files]
use ../../lib/matrix/cells.nu [expand-matrix-cells]
use ../../lib/matrix/expand.nu [expand-version-pairs]
use ../../lib/matrix/check/capabilities.nu [check-adapter-capabilities]

def main [] {
    print "Usage: nu scripts/ocmts.nu matrix <verb> [flags]"
    print ""
    print "Verbs:"
    print "  gen cypress          Generate cypress/e2e/<flow>/matrix.ts files"
    print "  list                 List expanded matrix cells (version pairs x browsers)"
    print "  list entries         Summarize matrix rules entries (one row per matrix_key)"
    print "  cell                 Compute cell_id and image refs for a matrix entry"
    print "  check capabilities   Validate adapter capabilities SSOT against platforms, flows, registry, and public-site files"
}

# Generate cypress/e2e/<flow>/matrix.ts files from the matrix SSOT under config/matrix/.
def "main gen cypress" [
    --check, # Compare generated output to existing files; error if different
] {
    let root = get-ocmts-root
    let rules = (load-matrix-rules $root)
    if $check {
        let results = (check-cypress-matrix-files $rules $root)
        let failures = ($results | where {|r| not $r.ok})
        if not ($failures | is-empty) {
            for f in $failures {
                print $"FAIL: ($f.path): ($f.diff)"
            }
            error make {msg: "cypress matrix check: generated output differs from on-disk files; run `matrix gen cypress` to update"}
        }
        print "cypress matrix check: OK"
    } else {
        let results = (write-cypress-matrix-files $rules $root)
        for r in $results {
            print $"Generated: ($r.path)"
        }
    }
}

# List expanded matrix cells: one row per version pair and browser.
def "main list" [--json] {
    let root = get-ocmts-root
    let rules = (load-matrix-rules $root)
    let cells = (expand-matrix-cells $rules)
    if $json {
        $cells | to json
    } else {
        $cells | table
    }
}

# nuon may store a lone version pair as a record; expand may return a table.
def normalize-pair-list [raw: any] {
    let desc = ($raw | describe)
    if ($desc | str starts-with "list") or ($desc | str starts-with "table") {
        return ($raw | each {|row| $row})
    }
    if ($raw | is-empty) {
        return []
    }
    [$raw]
}

# Version columns for list entries: unique versions from expand-version-pairs.
def matrix-entry-version-summary [entry: record] {
    let pairs = (normalize-pair-list (expand-version-pairs $entry))
    let sender_v = ($pairs | each {|p| $p.sender_version} | uniq | sort | str join ", ")
    let receiver_v = if ($entry.receiver? == null) {
        ""
    } else {
        $pairs | each {|p| $p.receiver_version} | uniq | sort | str join ", "
    }
    {sender_v: $sender_v, receiver_v: $receiver_v}
}

# One row per matrix_key from the loaded matrix rules (rules-level SSOT summary).
def matrix-entry-rows [matrix: record] {
    $matrix | items {|k, v|
        let versions = (matrix-entry-version-summary $v)
        {
            matrix_key: $k,
            flow: $v.flow_id,
            sender: $v.sender.platform,
            sender_v: $versions.sender_v,
            receiver: ($v.receiver?.platform? | default "-"),
            receiver_v: $versions.receiver_v,
        }
    } | sort-by flow matrix_key
}

# Summarize matrix rules entries: one row per matrix_key; versions from expanded pairs.
def "main list entries" [--json, --md] {
    if $json and $md {
        error make {msg: "--json and --md are mutually exclusive"}
    }
    let root = get-ocmts-root
    let rules = (load-matrix-rules $root)
    let rows = (matrix-entry-rows $rules.matrix)
    if $json {
        $rows | to json
    } else if $md {
        $rows | to md --pretty
    } else {
        $rows | table
    }
}

def "main cell" [
    --flow: string,
    --sender-platform: string,
    --sender-version: string,
    --receiver-platform: string = "",
    --receiver-version: string = "",
    --browser: string = "chrome",
    --json,
] {
    validate-cell-rules $flow $sender_platform $sender_version $browser $receiver_platform $receiver_version
    let cell = (compute-cell $flow $sender_platform $sender_version $browser $receiver_platform $receiver_version)
    let images = (resolve-images $sender_platform $sender_version
        --matrix-key $cell.matrix_key --flow-id $cell.flow_id)
    mut result = ($cell | insert images $images)
    if $cell.is_two_party {
        let recv_img = (resolve-receiver-image $receiver_platform $receiver_version
            --matrix-key $cell.matrix_key --flow-id $cell.flow_id)
        let mitm_img = (resolve-mitmproxy-image --matrix-key $cell.matrix_key --flow-id $cell.flow_id)
        $result = ($result | insert receiver_image $recv_img | insert mitmproxy_image $mitm_img)
    }
    if $json {
        $result | to json
    } else {
        print $"flow_id:           ($result.flow_id)"
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

# Validate adapter capabilities SSOT against platforms, flows, registry, and public-site files.
def "main check capabilities" [] {
    let root = (get-ocmts-root)
    let result = (check-adapter-capabilities $root)

    for $w in $result.warnings {
        print --stderr $"[matrix check capabilities] WARNING: ($w.message)"
    }
    let nwarn = ($result.warnings | length)
    if $nwarn > 0 {
        print --stderr $"[matrix check capabilities] ($nwarn) warning\(s\)"
    }

    if $result.provenance.skipped {
        print --stderr "[matrix check capabilities] INFO: site public dir not present; skipping provenance check"
    }

    if $result.ok {
        print "[matrix check capabilities] OK"
        return
    }

    print --stderr "[matrix check capabilities] FAIL"

    if ($result.platforms.missing_from_json | length) > 0 {
        print --stderr "Adapter keys missing from JSON (declared in platforms config):"
        for $k in $result.platforms.missing_from_json { print --stderr $"  - ($k)" }
    }
    if ($result.platforms.extra_in_json | length) > 0 {
        print --stderr "Adapter keys in JSON not in platforms config:"
        for $k in $result.platforms.extra_in_json { print --stderr $"  - ($k)" }
    }
    if ($result.platform_login.violations | length) > 0 {
        print --stderr "Platform login (platforms.nuon) violations:"
        for $v in $result.platform_login.violations { print --stderr $"  - ($v)" }
    }
    if ($result.completeness.missing | length) > 0 {
        print --stderr "Capabilities missing from adapter entries (declared in capability registry):"
        for $m in $result.completeness.missing { print --stderr $"  - ($m.adapter_key) missing: ($m.capability_key)" }
    }
    if ($result.flow_drift.unknown_names | length) > 0 {
        print --stderr "Capability names not in registry (used in flows or adapters):"
        for $n in $result.flow_drift.unknown_names { print --stderr $"  - ($n)" }
    }
    let r = $result.registry_cross
    if (($r.missing_keys | length) > 0) or (($r.extra_keys | length) > 0) or (($r.drift | length) > 0) {
        print --stderr "Supported-set drift vs registry.ts:"
        for $k in $r.missing_keys { print --stderr $"  - missing from supported set: ($k)" }
        for $k in $r.extra_keys { print --stderr $"  - extra in supported set: ($k)" }
        for $d in $r.drift { print --stderr $"  - ($d.key): expected [(($d.expected | str join ', '))], actual [(($d.actual | str join ', '))]" }
    }
    if ($result.provenance.violations | length) > 0 {
        print --stderr "Public file provenance violations:"
        for $v in $result.provenance.violations { print --stderr $"  - ($v.file): ($v.issue)" }
    }

    error make {msg: "matrix check capabilities: drift detected"}
}
