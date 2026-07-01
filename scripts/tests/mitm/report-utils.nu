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
        }
        let got = (load-meta-identity $tmp)
        [
            (assert-eq $got.matrix_key "login__nextcloud"
                "matrix_key is preserved")
            (assert-eq $got.flow_id "share-with"
                "explicit flow_id wins over scenario_module and matrix_key")
            (assert-eq $got.scenario_module "contact-wayf"
                "scenario_module stays explicit when present")
            (assert-eq $got.cell_id "cell-explicit"
                "cell_id is loaded from meta/cell.json")
            (assert-eq $got.run_id "run-explicit"
                "run_id is loaded from meta/run.json")
        ]
    }
}

def test-load-meta-identity-falls-back-to-scenario-module [] {
    test-log "\n[test-load-meta-identity-falls-back-to-scenario-module]"
    with-tmp-dir {|tmp|
        write-meta $tmp {
            matrix_key: "login__nextcloud"
            scenario_module: "contact-wayf"
            cell_id: "cell-scenario"
        } {
            execution_id: "run-scenario"
        }
        let got = (load-meta-identity $tmp)
        [
            (assert-eq $got.flow_id "contact-wayf"
                "scenario_module becomes flow_id when explicit flow_id is absent")
            (assert-eq $got.scenario_module "contact-wayf"
                "scenario_module stays explicit when used as fallback")
        ]
    }
}

def test-load-meta-identity-falls-back-to-matrix-key-prefix [] {
    test-log "\n[test-load-meta-identity-falls-back-to-matrix-key-prefix]"
    with-tmp-dir {|tmp|
        write-meta $tmp {
            matrix_key: "share-with__nextcloud__ocmgo"
            cell_id: "cell-matrix-key"
        } {
            execution_id: "run-matrix-key"
        }
        let got = (load-meta-identity $tmp)
        [
            (assert-eq $got.flow_id "share-with"
                "matrix_key prefix becomes flow_id when explicit fields are absent")
            (assert-eq $got.scenario_module "share-with"
                "scenario_module falls back to derived flow_id")
            (assert-eq $got.run_id "run-matrix-key"
                "run_id still loads when using matrix_key fallback")
        ]
    }
}

def test-load-meta-identity-falls-back-to-legacy-scenario [] {
    test-log "\n[test-load-meta-identity-falls-back-to-legacy-scenario]"
    with-tmp-dir {|tmp|
        write-meta $tmp {
            scenario: "contact-wayf"
            cell_id: "cell-legacy-scenario"
        } {
            execution_id: "run-legacy-scenario"
        }
        let got = (load-meta-identity $tmp)
        [
            (assert-eq $got.flow_id "contact-wayf"
                "legacy scenario becomes flow_id when tuple fields are absent")
            (assert-eq $got.scenario_module "contact-wayf"
                "scenario_module falls back to legacy scenario-derived flow_id")
            (assert-eq $got.run_id "run-legacy-scenario"
                "run_id still loads when using legacy scenario fallback")
        ]
    }
}

def test-load-meta-identity-prefers-matrix-key-over-legacy-scenario [] {
    test-log "\n[test-load-meta-identity-prefers-matrix-key-over-legacy-scenario]"
    with-tmp-dir {|tmp|
        write-meta $tmp {
            matrix_key: "share-with__nextcloud__ocmgo"
            scenario: "contact-wayf"
            cell_id: "cell-matrix-over-legacy"
        } {
            execution_id: "run-matrix-over-legacy"
        }
        let got = (load-meta-identity $tmp)
        [
            (assert-eq $got.flow_id "share-with"
                "matrix_key prefix wins over legacy scenario when tuple fields are absent")
            (assert-eq $got.scenario_module "share-with"
                "scenario_module falls back to matrix_key-derived flow_id")
            (assert-eq $got.run_id "run-matrix-over-legacy"
                "run_id still loads when matrix_key beats legacy scenario")
        ]
    }
}

def test-load-meta-identity-prefers-scenario-module-over-legacy-scenario [] {
    test-log "\n[test-load-meta-identity-prefers-scenario-module-over-legacy-scenario]"
    with-tmp-dir {|tmp|
        write-meta $tmp {
            scenario: "login"
            scenario_module: "contact-wayf"
            cell_id: "cell-both-scenario-fields"
        } {
            execution_id: "run-both"
        }
        let got = (load-meta-identity $tmp)
        [
            (assert-eq $got.flow_id "contact-wayf"
                "scenario_module wins over legacy scenario")
            (assert-eq $got.scenario_module "contact-wayf"
                "explicit scenario_module is preserved")
        ]
    }
}

def test-load-meta-identity-coalesces-matrix-key-from-run-json [] {
    test-log "\n[test-load-meta-identity-coalesces-matrix-key-from-run-json]"
    with-tmp-dir {|tmp|
        write-meta $tmp {
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
                "flow_id derives from coalesced run.json matrix_key")
            (assert-eq $got.scenario_module "share-with"
                "scenario_module falls back to coalesced matrix_key-derived flow_id")
        ]
    }
}

def main [] {
    test-log "=== mitm/report-utils Tests ==="
    let results = (
        (test-load-meta-identity-prefers-explicit-flow-id)
        | append (test-load-meta-identity-falls-back-to-scenario-module)
        | append (test-load-meta-identity-falls-back-to-matrix-key-prefix)
        | append (test-load-meta-identity-prefers-matrix-key-over-legacy-scenario)
        | append (test-load-meta-identity-falls-back-to-legacy-scenario)
        | append (test-load-meta-identity-prefers-scenario-module-over-legacy-scenario)
        | append (test-load-meta-identity-coalesces-matrix-key-from-run-json)
    ) | flatten
    run-suite "mitm/report-utils" $SUITE_PATH $results
}
