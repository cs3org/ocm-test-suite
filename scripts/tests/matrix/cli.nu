# Matrix CLI smoke tests.
# Run: nu scripts/tests/matrix/cli.nu

const SUITE_PATH = path self
const ENTRY_COLUMNS = [matrix_key flow sender sender_v receiver receiver_v]

use ../../lib/tests/assert.nu *
use ../../lib/tests/runner.nu [run-suite]
use ../../lib/tests/fixtures.nu [with-tmp-dir]

def repo-root [] {
    $SUITE_PATH | path dirname | path dirname | path dirname | path dirname
}

def ocmts-script [] {
    (repo-root) | path join "scripts/ocmts.nu"
}

def matrix-mod-script [] {
    (repo-root) | path join "scripts/domains/matrix/mod.nu"
}

def write-matrix-fixture [tmp_root: string] {
    mkdir ($tmp_root | path join "config/matrix/flows")

    ({browsers_default: ["chrome"]} | to nuon)
    | save --force ($tmp_root | path join "config/matrix/defaults.nuon")

    ({
        schema_version: 1
        platforms: {
            nextcloud: {version_lines: ["v32"]}
            ocmgo: {version_lines: ["v1"]}
        }
    } | to nuon)
    | save --force ($tmp_root | path join "config/matrix/platforms.nuon")

    ({
        schema_version: 1
        flow_id: "login"
        two_party: false
        enabled: true
        mitm: false
        browsers: ["chrome"]
        required_capabilities: {sender: [], receiver: []}
        include: {senders: ["nextcloud"]}
        versions_sender: {nextcloud: ["v32"]}
    } | to nuon)
    | save --force ($tmp_root | path join "config/matrix/flows/login.nuon")

    ({
        schema_version: 1
        flow_id: "share-with"
        two_party: true
        enabled: true
        mitm: false
        browsers: ["chrome"]
        required_capabilities: {sender: [], receiver: []}
        include: [{sender: ["nextcloud"], receiver: ["ocmgo"]}]
        versions_sender: {nextcloud: ["v32"]}
        versions_receiver: {ocmgo: ["v1"]}
    } | to nuon)
    | save --force ($tmp_root | path join "config/matrix/flows/share-with.nuon")

    ({
        schema_version: 1
        flow_id: "contact-wayf"
        two_party: true
        enabled: false
        mitm: true
        browsers: ["chrome"]
        required_capabilities: {sender: [], receiver: []}
        include: [{sender: ["nextcloud"], receiver: ["ocmgo"]}]
        versions_sender: {nextcloud: ["v32"]}
        versions_receiver: {ocmgo: ["v1"]}
    } | to nuon)
    | save --force ($tmp_root | path join "config/matrix/flows/contact-wayf.nuon")
}

def test-matrix-list-entries-json [] {
    test-log "\n[test-matrix-list-entries-json]"
    with-tmp-dir {|tmp|
        write-matrix-fixture $tmp
        with-env {OCMTS_ROOT: $tmp} {
            let out = (^nu (matrix-mod-script) list entries --json | complete)
            let rows = ($out.stdout | from json)
            let keys_ok = if ($rows | is-empty) {
                false
            } else {
                ($rows | first | columns | sort) == ($ENTRY_COLUMNS | sort)
            }
            let order = ($rows | get matrix_key)
            let two_party = ($rows
                | where matrix_key == "share-with__nextcloud__ocmgo"
                | first)
            [
                (assert-eq $out.exit_code 0
                    "matrix list entries --json exits 0")
                (assert-truthy $keys_ok
                    "matrix list entries --json rows have expected column keys")
                (assert-eq $order ["login__nextcloud" "share-with__nextcloud__ocmgo"]
                    "matrix list entries --json sorts by flow then matrix_key")
                (assert-eq ($rows | get flow | first) "login"
                    "matrix list entries --json first row is login flow")
                (assert-eq ($rows | get receiver | first) "-"
                    "matrix list entries --json one-party receiver is dash")
                (assert-eq ($rows | get receiver_v | first) ""
                    "matrix list entries --json one-party receiver_v is empty")
                (assert-eq $two_party.sender "nextcloud"
                    "matrix list entries --json two-party sender is nextcloud")
                (assert-eq $two_party.sender_v "v32"
                    "matrix list entries --json two-party sender_v is v32")
                (assert-eq $two_party.receiver "ocmgo"
                    "matrix list entries --json two-party receiver is ocmgo")
                (assert-eq $two_party.receiver_v "v1"
                    "matrix list entries --json two-party receiver_v is v1")
            ]
        }
    }
}

def test-matrix-list-entries-md [] {
    test-log "\n[test-matrix-list-entries-md]"
    with-tmp-dir {|tmp|
        write-matrix-fixture $tmp
        with-env {OCMTS_ROOT: $tmp} {
            let out = (^nu (matrix-mod-script) list entries --md | complete)
            let md = $out.stdout
            [
                (assert-eq $out.exit_code 0
                    "matrix list entries --md exits 0")
                (assert-string-contains $md "matrix_key"
                    "matrix list entries --md header includes matrix_key")
                (assert-string-contains $md "receiver_v"
                    "matrix list entries --md header includes receiver_v")
                (assert-string-contains $md "login__nextcloud"
                    "matrix list entries --md includes login__nextcloud row")
                (assert-string-contains $md "share-with__nextcloud__ocmgo"
                    "matrix list entries --md includes share-with two-party row")
            ]
        }
    }
}

def test-matrix-list-entries-json-md-errors [] {
    test-log "\n[test-matrix-list-entries-json-md-errors]"
    with-tmp-dir {|tmp|
        write-matrix-fixture $tmp
        with-env {OCMTS_ROOT: $tmp} {
            let out = (^nu (matrix-mod-script) list entries --json --md | complete)
            [
                (assert-eq $out.exit_code 1
                    "matrix list entries --json --md exits 1")
                (assert-string-contains $out.stderr "mutually exclusive"
                    "matrix list entries --json --md names mutually exclusive flags")
            ]
        }
    }
}

def test-matrix-list-entries-cross-product-versions [] {
    test-log "\n[test-matrix-list-entries-cross-product-versions]"
    with-tmp-dir {|tmp|
        mkdir ($tmp | path join "config/matrix/flows")
        ({browsers_default: ["chrome"]} | to nuon)
        | save --force ($tmp | path join "config/matrix/defaults.nuon")
        ({
            schema_version: 1
            platforms: {
                nextcloud: {version_lines: ["v32", "v33"]}
                ocmgo: {version_lines: ["v1", "v2"]}
            }
        } | to nuon)
        | save --force ($tmp | path join "config/matrix/platforms.nuon")
        ({
            schema_version: 1
            flow_id: "share-with"
            two_party: true
            enabled: true
            mitm: false
            browsers: ["chrome"]
            required_capabilities: {sender: [], receiver: []}
            include: [{sender: ["nextcloud"], receiver: ["ocmgo"]}]
            versions_sender: {nextcloud: ["v32", "v33"]}
            versions_receiver: {ocmgo: ["v1", "v2"]}
        } | to nuon)
        | save --force ($tmp | path join "config/matrix/flows/share-with.nuon")
        with-env {OCMTS_ROOT: $tmp} {
            let out = (^nu (matrix-mod-script) list entries --json | complete)
            let rows = ($out.stdout | from json)
            let row = ($rows | where matrix_key == "share-with__nextcloud__ocmgo" | first)
            [
                (assert-eq $out.exit_code 0
                    "matrix list entries cross_product exits 0")
                (assert-eq ($rows | length) 1
                    "matrix list entries cross_product emits one summary row")
                (assert-eq $row.sender_v "v32, v33"
                    "matrix list entries sender_v aggregates cross_product sender versions")
                (assert-eq $row.receiver_v "v1, v2"
                    "matrix list entries receiver_v aggregates cross_product receiver versions")
            ]
        }
    }
}

def test-matrix-list-entries-explicit-pairs-versions [] {
    test-log "\n[test-matrix-list-entries-explicit-pairs-versions]"
    with-tmp-dir {|tmp|
        mkdir ($tmp | path join "config/matrix/flows")
        ({browsers_default: ["chrome"]} | to nuon)
        | save --force ($tmp | path join "config/matrix/defaults.nuon")
        ({
            schema_version: 1
            platforms: {
                nextcloud: {version_lines: ["v32", "v33"]}
                ocmgo: {version_lines: ["v1"]}
            }
        } | to nuon)
        | save --force ($tmp | path join "config/matrix/platforms.nuon")
        ({
            schema_version: 1
            flow_id: "contact-wayf"
            two_party: true
            enabled: true
            mitm: true
            browsers: ["chrome"]
            required_capabilities: {sender: [], receiver: []}
            include: [{
                sender: ["nextcloud"]
                receiver: ["ocmgo"]
                version_pairing: "explicit_pairs"
                version_pairs: [{sender: "v32", receiver: "v1"}]
            }]
            versions_sender: {nextcloud: ["v32", "v33"]}
            versions_receiver: {ocmgo: ["v1"]}
        } | to nuon)
        | save --force ($tmp | path join "config/matrix/flows/contact-wayf.nuon")
        with-env {OCMTS_ROOT: $tmp} {
            let out = (^nu (matrix-mod-script) list entries --json | complete)
            let rows = ($out.stdout | from json)
            let row = ($rows | where matrix_key == "contact-wayf__nextcloud__ocmgo" | first)
            [
                (assert-eq $out.exit_code 0
                    "matrix list entries explicit_pairs exits 0")
                (assert-eq ($rows | length) 1
                    "matrix list entries explicit_pairs emits one summary row")
                (assert-eq $row.sender_v "v32"
                    "matrix list entries sender_v reflects explicit_pairs not version_lines")
                (assert-eq $row.receiver_v "v1"
                    "matrix list entries receiver_v reflects explicit_pairs")
            ]
        }
    }
}

def test-matrix-list-entries-routed [] {
    test-log "\n[test-matrix-list-entries-routed]"
    with-tmp-dir {|tmp|
        write-matrix-fixture $tmp
        ^ln -s ((repo-root) | path join "scripts") ($tmp | path join "scripts")
        with-env {OCMTS_ROOT: $tmp} {
            let table_out = (^nu (ocmts-script) matrix list entries | complete)
            let json_out = (^nu (ocmts-script) matrix list entries --json | complete)
            let md_out = (^nu (ocmts-script) matrix list entries --md | complete)
            let json_md_out = (^nu (ocmts-script) matrix list entries --json --md | complete)
            let rows = ($json_out.stdout | from json)
            [
                (assert-eq $table_out.exit_code 0
                    "ocmts matrix list entries default table exits 0")
                (assert-string-contains $table_out.stdout "matrix_key"
                    "ocmts matrix list entries default table includes matrix_key column")
                (assert-string-contains $table_out.stdout "login__nextcloud"
                    "ocmts matrix list entries default table includes login row")
                (assert-eq $json_out.exit_code 0
                    "ocmts matrix list entries --json exits 0")
                (assert-eq ($rows | get matrix_key)
                    ["login__nextcloud" "share-with__nextcloud__ocmgo"]
                    "ocmts matrix list entries --json sorts by flow then matrix_key")
                (assert-eq $md_out.exit_code 0
                    "ocmts matrix list entries --md exits 0")
                (assert-string-contains $md_out.stdout "receiver_v"
                    "ocmts matrix list entries --md header includes receiver_v")
                (assert-string-contains $md_out.stdout "share-with__nextcloud__ocmgo"
                    "ocmts matrix list entries --md includes share-with two-party row")
                (assert-eq $json_md_out.exit_code 1
                    "ocmts matrix list entries --json --md exits 1")
                (assert-string-contains $json_md_out.stderr "mutually exclusive"
                    "ocmts matrix list entries --json --md names mutually exclusive flags")
            ]
        }
    }
}

def test-matrix-help-lists-entries [] {
    test-log "\n[test-matrix-help-lists-entries]"
    let out = (^nu (ocmts-script) matrix | complete)
    [
        (assert-eq $out.exit_code 0
            "matrix domain help exits 0")
        (assert-string-contains $out.stdout "list entries"
            "matrix domain help advertises list entries subcommand")
        (assert-string-contains $out.stdout "version pairs x browsers"
            "matrix domain help names version-pair and browser expansion for list")
    ]
}

def main [] {
    test-log "=== matrix/cli Tests ==="
    let results = (
        (test-matrix-list-entries-json)
        | append (test-matrix-list-entries-md)
        | append (test-matrix-list-entries-json-md-errors)
        | append (test-matrix-list-entries-cross-product-versions)
        | append (test-matrix-list-entries-explicit-pairs-versions)
        | append (test-matrix-list-entries-routed)
        | append (test-matrix-help-lists-entries)
    ) | flatten
    run-suite "matrix/cli" $SUITE_PATH $results
}
