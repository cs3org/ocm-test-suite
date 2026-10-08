# MITM report utility tests.
# Run: nu scripts/tests/mitm/report-utils.nu

const SUITE_PATH = path self

use ../../lib/mitm/report-utils.nu [
    load-meta-identity participants-from-roles md-participants-preface
    resolve-from-endpoint resolve-to-endpoint infer-from-role infer-to-role
]
use ../../lib/tests/assert.nu *
use ../../lib/tests/runner.nu [run-suite]
use ../../lib/tests/fixtures.nu [with-tmp-dir]

def write-meta [tmp_root: string, cell: record, run: record] {
    mkdir ($tmp_root | path join "meta")
    ($cell | to json) | save --force ($tmp_root | path join "meta/cell.json")
    ($run | to json) | save --force ($tmp_root | path join "meta/run.json")
}

def test-load-meta-identity-prefers-explicit-flow-id [] {
    test-log "\n[test-load-meta-identity-prefers-explicit-flow-id]"
    with-tmp-dir {|tmp|
        write-meta $tmp {
            matrix_key: "login__nextcloud"
            flow_id: "share-with"
            scenario_module: "contact-wayf"
            cell_id: "cell-explicit"
        } {
            execution_id: "run-explicit"
            matrix_key: "login__nextcloud"
        }
        let got = (load-meta-identity $tmp)
        [
            (assert-eq $got.matrix_key "login__nextcloud"
                "matrix_key comes from run.json")
            (assert-eq $got.flow_id "share-with"
                "flow_id comes from canonical cell.flow_id")
            (assert-eq $got.cell_id "cell-explicit"
                "cell_id is loaded from meta/cell.json")
            (assert-eq $got.run_id "run-explicit"
                "run_id is loaded from meta/run.json")
        ]
    }
}

def test-load-meta-identity-coalesces-matrix-key-from-run-json [] {
    test-log "\n[test-load-meta-identity-coalesces-matrix-key-from-run-json]"
    with-tmp-dir {|tmp|
        write-meta $tmp {
            flow_id: "share-with"
            cell_id: "cell-run-matrix-key"
        } {
            execution_id: "run-coalesced-matrix"
            matrix_key: "share-with__nextcloud__ocmgo"
        }
        let got = (load-meta-identity $tmp)
        [
            (assert-eq $got.matrix_key "share-with__nextcloud__ocmgo"
                "matrix_key coalesces from run.json when cell omits it")
            (assert-eq $got.flow_id "share-with"
                "flow_id comes from canonical cell.flow_id")
        ]
    }
}

def test-load-meta-identity-errors-without-flow-id [] {
    test-log "\n[test-load-meta-identity-errors-without-flow-id]"
    with-tmp-dir {|tmp|
        write-meta $tmp {
            cell_id: "cell-missing-flow-id"
            matrix_key: "login__nextcloud"
        } {
            execution_id: "run-missing-flow-id"
            matrix_key: "login__nextcloud"
        }
        let result = (try { load-meta-identity $tmp; "no-error" } catch {|e| "error"})
        [
            (assert-eq $result "error"
                "load-meta-identity errors when cell.flow_id is absent")
        ]
    }
}

def test-load-meta-identity-errors-with-scenario-module-only [] {
    test-log "\n[test-load-meta-identity-errors-with-scenario-module-only]"
    with-tmp-dir {|tmp|
        write-meta $tmp {
            cell_id: "cell-scenario-module-only"
            scenario_module: "contact-wayf"
            matrix_key: "contact-wayf__nextcloud"
        } {
            execution_id: "run-scenario-module-only"
            matrix_key: "contact-wayf__nextcloud"
        }
        let result = (try { load-meta-identity $tmp; "no-error" } catch {|e| "error"})
        [
            (assert-eq $result "error"
                "load-meta-identity errors when only scenario_module is present")
        ]
    }
}

def test-load-meta-identity-errors-with-legacy-scenario-only [] {
    test-log "\n[test-load-meta-identity-errors-with-legacy-scenario-only]"
    with-tmp-dir {|tmp|
        write-meta $tmp {
            cell_id: "cell-legacy-scenario-only"
            scenario: "login"
            matrix_key: "login__nextcloud"
        } {
            execution_id: "run-legacy-scenario-only"
            matrix_key: "login__nextcloud"
        }
        let result = (try { load-meta-identity $tmp; "no-error" } catch {|e| "error"})
        [
            (assert-eq $result "error"
                "load-meta-identity errors when only legacy scenario is present")
        ]
    }
}

def test-load-meta-identity-errors-on-malformed-cell-json [] {
    test-log "\n[test-load-meta-identity-errors-on-malformed-cell-json]"
    with-tmp-dir {|tmp|
        mkdir ($tmp | path join "meta")
        "{ not valid json" | save --force ($tmp | path join "meta/cell.json")
        ({
            execution_id: "run-malformed-cell"
            matrix_key: "login__nextcloud"
        } | to json) | save --force ($tmp | path join "meta/run.json")
        let result = (try { load-meta-identity $tmp; "no-error" } catch {|e| "error"})
        [
            (assert-eq $result "error"
                "load-meta-identity fails fast on malformed meta/cell.json")
        ]
    }
}

def test-load-meta-identity-errors-on-malformed-run-json [] {
    test-log "\n[test-load-meta-identity-errors-on-malformed-run-json]"
    with-tmp-dir {|tmp|
        mkdir ($tmp | path join "meta")
        ({
            flow_id: "share-with"
            cell_id: "cell-malformed-run"
        } | to json) | save --force ($tmp | path join "meta/cell.json")
        "{ not valid json" | save --force ($tmp | path join "meta/run.json")
        let result = (try { load-meta-identity $tmp; "no-error" } catch {|e| "error"})
        [
            (assert-eq $result "error"
                "load-meta-identity fails fast on malformed meta/run.json")
        ]
    }
}

def test-endpoint-contract [] {
    let legacy = {
        sender: {ipv4: "10.42.0.2", hosts: ["nextcloud1.docker"]},
        receiver: {ipv4: "10.42.0.3", hosts: ["cernbox2.docker"]},
        mitm: {ipv4: "10.42.0.4", hosts: ["mitm"]},
    }
    let v2 = {
        sender: {endpoints: [
            {service: "sender", ipv4: "10.42.0.2", hosts: ["nextcloud1.docker" "sender"]},
            {service: "sender-hub", ipv4: "10.42.0.5", hosts: ["jupyterhub1.docker" "sender-hub"]},
        ]},
        receiver: {endpoints: [
            {service: "receiver", ipv4: "10.42.0.3", hosts: ["cernbox2.docker" "receiver"]},
            {service: "receiver-revad-gateway", ipv4: "10.42.0.6", hosts: ["receiver-revad-gateway"]},
        ]},
        mitm: {endpoints: [{service: "mitm", ipv4: "10.42.0.4", hosts: ["mitm"]}]},
    }
    let legacy_preface = "## Participants\n\n- sender: nextcloud1.docker (10.42.0.2)\n- receiver: cernbox2.docker (10.42.0.3)\n- mitm: mitm (10.42.0.4)\n"
    let ambiguity = {sender: {endpoints: [
        {service: "one", ipv4: "10.42.0.9", hosts: ["same"]},
        {service: "two", ipv4: "10.42.0.9", hosts: ["same"]},
    ]}}
    let empty_v2 = {sender: {endpoints: [], ipv4: "stale", hosts: ["stale"]}}
    [
        (assert-eq (md-participants-preface (participants-from-roles $legacy)) $legacy_preface "v1 preface bytes unchanged")
        (assert-eq (md-participants-preface (participants-from-roles $v2)) $legacy_preface "v2 primaries preserve participant preface")
        (assert-eq (resolve-from-endpoint "10.42.0.6" $v2) {role: "receiver", service: "receiver-revad-gateway", host: "receiver-revad-gateway"} "gateway owns received OCM client flows")
        (assert-eq (resolve-to-endpoint "jupyterhub1.docker" "10.42.0.5" $v2) {role: "sender", service: "sender-hub", host: "jupyterhub1.docker"} "hub is sender endpoint")
        (assert-eq (resolve-to-endpoint "" "jupyterhub1.docker" $v2 | get role) "sender" "server hostname fallback works")
        (assert-eq (resolve-to-endpoint "NEXTCLOUD1.DOCKER" "10.42.0.3" $v2 | get role) "sender" "host ownership precedes server IP")
        (assert-eq (infer-from-role "10.42.0.6" $v2) "receiver" "old inference export delegates")
        (assert-eq (infer-to-role "jupyterhub1.docker" "" $v2) "sender" "old destination export delegates")
        (assert-eq (resolve-from-endpoint "10.42.0.3" $legacy) {role: "receiver", service: "", host: "cernbox2.docker"} "v1 fallback synthesizes primary")
        (assert-eq (infer-to-role "nextcloud1.docker" "10.42.0.3" $legacy) "sender" "legacy host precedence remains")
        (assert-eq (infer-to-role "" "jupyterhub1.docker" $legacy) "unknown" "v1 hostname fallback is not introduced")
        (assert-eq (resolve-from-endpoint "" $v2 | get role) "unknown" "empty IP does not match")
        (assert-eq (resolve-to-endpoint "" "" $v2 | get role) "unknown" "empty destination does not match")
        (assert-eq (participants-from-roles {} | get sender_host) "" "missing roles default empty")
        (assert-eq (participants-from-roles $empty_v2 | get sender_host) "" "empty endpoints never read stale scalar")
        (assert-eq (resolve-from-endpoint "10.42.0.9" $ambiguity | get role) "unknown" "ambiguous source fails closed")
        (assert-eq (resolve-to-endpoint "same" "" $ambiguity | get role) "unknown" "ambiguous destination fails closed")
    ]
}

def main [] {
    test-log "=== mitm/report-utils Tests ==="
    let results = (
        (test-load-meta-identity-prefers-explicit-flow-id)
        | append (test-load-meta-identity-coalesces-matrix-key-from-run-json)
        | append (test-load-meta-identity-errors-without-flow-id)
        | append (test-load-meta-identity-errors-with-scenario-module-only)
        | append (test-load-meta-identity-errors-with-legacy-scenario-only)
        | append (test-load-meta-identity-errors-on-malformed-cell-json)
        | append (test-load-meta-identity-errors-on-malformed-run-json)
        | append (test-endpoint-contract)
    ) | flatten
    run-suite "mitm/report-utils" $SUITE_PATH $results
}
