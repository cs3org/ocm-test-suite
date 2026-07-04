# Flow Topology SSOT Tests.
# Run: nu scripts/tests/matrix/topology.nu
# Returns exit 0 on all pass, exit 1 with details on failure.

const SUITE_PATH = path self

use ../../lib/tests/assert.nu *
use ../../lib/tests/runner.nu [run-suite]
use ../../lib/matrix/topology.nu [flow-is-two-party assert-topology-matches]
use ../../lib/matrix/cell.nu [compute-cell]

def test-login-is-one-party [] {
    test-log "\n[test-login-is-one-party]"
    let result = (flow-is-two-party "login")
    [
        (assert-eq $result false "login flow has two_party=false")
    ]
}

def test-share-with-is-two-party [] {
    test-log "\n[test-share-with-is-two-party]"
    let result = (flow-is-two-party "share-with")
    [
        (assert-eq $result true "share-with flow has two_party=true")
    ]
}

def test-assert-topology-matches-ok [] {
    test-log "\n[test-assert-topology-matches-ok]"
    let errored = try {
        assert-topology-matches "login" false "test"
        false
    } catch {
        true
    }
    [
        (assert-eq $errored false "assert-topology-matches passes when derived matches canonical")
    ]
}

def test-assert-topology-mismatch-errors [] {
    test-log "\n[test-assert-topology-mismatch-errors]"
    let got_mismatch_msg = try {
        assert-topology-matches "login" true "test"
        false
    } catch {|e|
        ($e.msg | str contains "Topology mismatch")
    }
    [
        (assert-truthy $got_mismatch_msg "assert-topology-matches errors with 'Topology mismatch' on wrong derived value")
    ]
}

def test-compute-cell-login-one-party-ok [] {
    test-log "\n[test-compute-cell-login-one-party-ok]"
    let cell = (compute-cell "login" "nextcloud" "v33" "chrome")
    [
        (assert-eq $cell.is_two_party false "login one-party cell has is_two_party=false")
        (assert-eq $cell.matrix_key "login__nextcloud"
            "login one-party cell has matrix_key login__nextcloud")
        (assert-eq $cell.cell_id "login__nextcloud-v33"
            "login one-party cell_id shape")
        (assert-eq $cell.artifact_name "cell-login-nextcloud-v33"
            "login one-party artifact_name shape")
    ]
}

def test-compute-cell-login-with-receiver-errors [] {
    test-log "\n[test-compute-cell-login-with-receiver-errors]"
    let got_msg = try {
        compute-cell "login" "nextcloud" "v33" "chrome" "nextcloud" "v33"
        ""
    } catch {|e|
        $e.msg
    }
    [
        (assert-string-contains $got_msg "one-party"
            "compute-cell errors when receiver given to one-party flow")
        (assert-string-contains $got_msg "--receiver-platform"
            "compute-cell spurious receiver error names --receiver-platform")
    ]
}

def test-compute-cell-share-with-two-party-ok [] {
    test-log "\n[test-compute-cell-share-with-two-party-ok]"
    let cell = (compute-cell "share-with" "nextcloud" "v33" "chrome" "nextcloud" "v33")
    [
        (assert-eq $cell.is_two_party true "share-with two-party cell has is_two_party=true")
        (assert-eq $cell.matrix_key "share-with__nextcloud__nextcloud"
            "share-with two-party matrix_key shape")
        (assert-eq $cell.cell_id "share-with__nextcloud-v33__nextcloud-v33"
            "share-with two-party cell_id shape")
        (assert-eq $cell.artifact_name "cell-share-with-nextcloud-v33-nextcloud-v33"
            "share-with two-party artifact_name shape")
    ]
}

def test-compute-cell-share-with-no-receiver-errors [] {
    test-log "\n[test-compute-cell-share-with-no-receiver-errors]"
    let got_msg = try {
        compute-cell "share-with" "nextcloud" "v33" "chrome"
        ""
    } catch {|e|
        $e.msg
    }
    [
        (assert-string-contains $got_msg "requires --receiver-platform"
            "compute-cell errors when no receiver given for two-party flow")
    ]
}

def main [] {
    let results = ([]
        | append (test-login-is-one-party)
        | append (test-share-with-is-two-party)
        | append (test-assert-topology-matches-ok)
        | append (test-assert-topology-mismatch-errors)
        | append (test-compute-cell-login-one-party-ok)
        | append (test-compute-cell-login-with-receiver-errors)
        | append (test-compute-cell-share-with-two-party-ok)
        | append (test-compute-cell-share-with-no-receiver-errors)
    )
    run-suite "matrix/topology" $SUITE_PATH $results
}
