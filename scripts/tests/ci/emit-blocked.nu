# emit-blocked command tests.
# Run: nu scripts/tests/ci/emit-blocked.nu

const SUITE_PATH = path self

use ../../lib/tests/assert.nu *
use ../../lib/tests/runner.nu [run-suite]
use ../../lib/tests/fixtures.nu [with-tmp-dir]

def repo-root [] {
    $SUITE_PATH | path dirname | path dirname | path dirname | path dirname
}

def emit-blocked-script [] {
    (repo-root) | path join "scripts/domains/ci/emit-blocked.nu"
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
        mitm: true
        browsers: ["chrome"]
        required_capabilities: {sender: [], receiver: []}
        include: [{sender: ["nextcloud"], receiver: ["nextcloud"]}]
        versions_sender: {nextcloud: ["v32"]}
        versions_receiver: {nextcloud: ["v32"]}
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

def test-emit-blocked-rejects-absent-tuple [] {
    test-log "\n[test-emit-blocked-rejects-absent-tuple]"
    with-tmp-dir {|tmp|
        write-matrix-fixture $tmp
        with-env {OCMTS_ROOT: $tmp} {
            let out = (^nu (emit-blocked-script)
                --execution-id 20260101t000000-aaaaaaaa
                --flow share-with
                --sender-platform nextcloud
                --sender-version v32
                --receiver-platform ocmgo
                --receiver-version v1
                --failure-reason "blocked by prereq"
                | complete)
            [
                (assert-eq $out.exit_code 1
                    "emit-blocked absent tuple exits 1")
                (assert-string-contains $out.stderr "not in config/matrix"
                    "emit-blocked absent tuple error names config/matrix")
            ]
        }
    }
}

def test-emit-blocked-rejects-disabled-tuple [] {
    test-log "\n[test-emit-blocked-rejects-disabled-tuple]"
    with-tmp-dir {|tmp|
        write-matrix-fixture $tmp
        with-env {OCMTS_ROOT: $tmp} {
            let out = (^nu (emit-blocked-script)
                --execution-id 20260101t000000-aaaaaaaa
                --flow contact-wayf
                --sender-platform nextcloud
                --sender-version v32
                --receiver-platform ocmgo
                --receiver-version v1
                --failure-reason "blocked by prereq"
                | complete)
            [
                (assert-eq $out.exit_code 1
                    "emit-blocked disabled tuple exits 1")
                (assert-string-contains $out.stderr "disabled"
                    "emit-blocked disabled tuple error names disabled status")
                (assert-string-contains $out.stderr "contact-wayf__nextcloud__ocmgo"
                    "emit-blocked disabled tuple error names matrix_key")
            ]
        }
    }
}

def test-emit-blocked-writes-enabled-artifact [] {
    test-log "\n[test-emit-blocked-writes-enabled-artifact]"
    with-tmp-dir {|tmp|
        write-matrix-fixture $tmp
        with-env {OCMTS_ROOT: $tmp} {
            let out = (^nu (emit-blocked-script)
                --execution-id 20260101t000000-aaaaaaaa
                --flow login
                --sender-platform nextcloud
                --sender-version v32
                --failure-reason "blocked by prereq"
                | complete)
            let base = ($tmp | path join "artifacts" "login" "nextcloud-v32" "20260101t000000-aaaaaaaa")
            let cell_meta = (open ($base | path join "meta/cell.json"))
            let run_meta = (open ($base | path join "meta/run.json"))
            let result_meta = (open ($base | path join "meta/result.v1.json"))
            [
                (assert-eq $out.exit_code 0
                    "emit-blocked enabled tuple exits 0")
                (assert-string-contains $out.stdout "Blocked artifact written to"
                    "emit-blocked success prints artifact path")
                (assert-truthy (($base | path join "meta/cell.json") | path exists)
                    "emit-blocked writes meta/cell.json")
                (assert-truthy (($base | path join "meta/run.json") | path exists)
                    "emit-blocked writes meta/run.json")
                (assert-truthy (($base | path join "meta/result.v1.json") | path exists)
                    "emit-blocked writes meta/result.v1.json")
                (assert-eq $cell_meta.matrix_key "login__nextcloud"
                    "emit-blocked writes validated matrix_key into cell metadata")
                (assert-truthy (not ("scenario_module" in ($cell_meta | columns)))
                    "emit-blocked cell.json omits scenario_module")
                (assert-eq $run_meta.matrix_key "login__nextcloud"
                    "emit-blocked writes matrix_key into terminal run.json")
                (assert-eq $result_meta.matrix_key "login__nextcloud"
                    "emit-blocked writes matrix_key into terminal result.v1.json")
            ]
        }
    }
}

def test-emit-blocked-writes-two-party-artifact [] {
    test-log "\n[test-emit-blocked-writes-two-party-artifact]"
    with-tmp-dir {|tmp|
        write-matrix-fixture $tmp
        with-env {OCMTS_ROOT: $tmp} {
            let out = (^nu (emit-blocked-script)
                --execution-id 20260101t000000-bbbbbbbb
                --flow share-with
                --sender-platform nextcloud
                --sender-version v32
                --receiver-platform nextcloud
                --receiver-version v32
                --failure-reason "blocked by prereq"
                | complete)
            let base = ($tmp | path join "artifacts" "share-with" "nextcloud-v32-nextcloud-v32" "20260101t000000-bbbbbbbb")
            let cell_meta = (open ($base | path join "meta/cell.json"))
            let run_meta = (open ($base | path join "meta/run.json"))
            let result_meta = (open ($base | path join "meta/result.v1.json"))
            [
                (assert-eq $out.exit_code 0
                    "emit-blocked two-party enabled tuple exits 0")
                (assert-eq $cell_meta.matrix_key "share-with__nextcloud__nextcloud"
                    "emit-blocked two-party writes matrix_key into cell metadata")
                (assert-eq $cell_meta.cell_id "share-with__nextcloud-v32__nextcloud-v32"
                    "emit-blocked two-party cell_id shape")
                (assert-eq $cell_meta.artifact_name "cell-share-with-nextcloud-v32-nextcloud-v32"
                    "emit-blocked two-party artifact_name shape")
                (assert-eq ($cell_meta.is_two_party? | default false) true
                    "emit-blocked two-party is_two_party true")
                (assert-eq $run_meta.matrix_key "share-with__nextcloud__nextcloud"
                    "emit-blocked two-party writes matrix_key into run.json")
                (assert-eq $result_meta.matrix_key "share-with__nextcloud__nextcloud"
                    "emit-blocked two-party writes matrix_key into result.v1.json")
                (assert-eq ($result_meta.status? | default "") "blocked"
                    "emit-blocked two-party result status is blocked")
            ]
        }
    }
}

def test-emit-blocked-rejects-flow-id-flag [] {
    test-log "\n[test-emit-blocked-rejects-flow-id-flag]"
    with-tmp-dir {|tmp|
        write-matrix-fixture $tmp
        with-env {OCMTS_ROOT: $tmp} {
            let out = (^nu (emit-blocked-script)
                --execution-id 20260101t000000-aaaaaaaa
                --flow-id login
                --sender-platform nextcloud
                --sender-version v32
                --failure-reason "blocked by prereq"
                | complete)
            [
                (assert-eq $out.exit_code 1
                    "emit-blocked --flow-id exits 1")
                (assert-truthy (
                    ($out.stderr | str contains "unknown_flag")
                    or ($out.stderr | str contains "doesn't have flag `flow-id`")
                    or ($out.stderr | str contains "doesn't have flag 'flow-id'")
                ) "emit-blocked stderr reports unknown --flow-id flag")
            ]
        }
    }
}

def main [] {
    test-log "=== ci/emit-blocked Tests ==="
    let results = (
        (test-emit-blocked-rejects-absent-tuple)
        | append (test-emit-blocked-rejects-disabled-tuple)
        | append (test-emit-blocked-writes-enabled-artifact)
        | append (test-emit-blocked-writes-two-party-artifact)
        | append (test-emit-blocked-rejects-flow-id-flag)
    ) | flatten
    run-suite "ci/emit-blocked" $SUITE_PATH $results
}
