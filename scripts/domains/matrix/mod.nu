# Matrix domain: test matrix management.

use ../../lib/cell.nu [compute-cell validate-cell-rules]
use ../../lib/images.nu [resolve-images resolve-receiver-image resolve-mitmproxy-image]
use ../../lib/domain/core/ocmts-root.nu [get-ocmts-root]
use ../../lib/matrix-rules-gen.nu [generate-matrix-rules write-generated-matrix-rules]
use ../../lib/matrix-cypress-gen.nu [write-cypress-matrix-files check-cypress-matrix-files]
use ../../lib/matrix-cells.nu [expand-matrix-cells]

def main [] {
    print "Usage: nu scripts/ocmts.nu matrix <verb> [flags]"
    print ""
    print "Verbs:"
    print "  gen                Generate config/matrix-rules.nuon from config/matrix/"
    print "  gen cypress        Generate cypress/e2e/<flow>/matrix.ts files"
    print "  list               List all matrix cells from config/matrix-rules.nuon"
    print "  cell               Compute cell_id and image refs for a matrix entry"
}

# Generate config/matrix-rules.nuon from the modular SSOT at config/matrix/.
def "main gen" [
    --matrix-dir: string = "", # SSOT folder (default: <root>/config/matrix)
    --out-path: string = "",   # Output file (default: <root>/config/matrix-rules.nuon)
    --check,                   # Compare generated output to existing file; error if different
] {
    let root = get-ocmts-root
    let matrix_dir = if not ($matrix_dir | is-empty) {
        $matrix_dir
    } else {
        $root | path join "config/matrix"
    }
    let out = if not ($out_path | is-empty) {
        $out_path
    } else {
        $root | path join "config/matrix-rules.nuon"
    }

    if $check {
        let generated = (generate-matrix-rules $matrix_dir)
        if not ($out | path exists) {
            error make {msg: $"matrix-rules check: output file not found: ($out)"}
        }
        let existing = open $out
        if $generated != $existing {
            error make {msg: "matrix-rules check: generated output differs from on-disk file; run `matrix gen` to update"}
        }
        print "matrix-rules check: OK"
    } else {
        write-generated-matrix-rules $matrix_dir $out
        print $"Generated: ($out)"
    }
}

# Generate cypress/e2e/<flow>/matrix.ts files from config/matrix-rules.nuon.
def "main gen cypress" [
    --check, # Compare generated output to existing files; error if different
] {
    let root = get-ocmts-root
    let rules = open ($root | path join "config/matrix-rules.nuon")
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

# List all matrix cells defined in config/matrix-rules.nuon.
def "main list" [--json] {
    let root = get-ocmts-root
    let rules = open ($root | path join "config/matrix-rules.nuon")
    let cells = (expand-matrix-cells $rules)
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
    let flow_id = (validate-cell-rules
        $scenario $sender_platform $sender_version $browser
        $receiver_platform $receiver_version)
    let cell = (compute-cell
        $scenario $sender_platform $sender_version $browser
        $receiver_platform $receiver_version $flow_id)
    let images = (resolve-images $sender_platform $sender_version
        --scenario $scenario --flow-id $flow_id)
    mut result = ($cell | insert images $images)
    if $cell.is_two_party {
        let recv_img = (resolve-receiver-image $receiver_platform $receiver_version
            --scenario $scenario --flow-id $flow_id)
        let mitm_img = (resolve-mitmproxy-image --scenario $scenario --flow-id $flow_id)
        $result = ($result | insert receiver_image $recv_img | insert mitmproxy_image $mitm_img)
    }
    if $json {
        $result | to json
    } else {
        print $"flow_id:           ($result.flow_id)"
        print $"scenario_module:   ($result.scenario_module)"
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
