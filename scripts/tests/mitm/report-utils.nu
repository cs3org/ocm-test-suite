# MITM report utility tests.
# Run: nu scripts/tests/mitm/report-utils.nu

const SUITE_PATH = path self

use ../../lib/mitm/report-utils.nu [load-meta-identity]
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
    ) | flatten
    run-suite "mitm/report-utils" $SUITE_PATH $results
}
