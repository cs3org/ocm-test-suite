# Matrix check cells runnable tests.
# Run: nu scripts/tests/matrix/check-cells.nu

const SUITE_PATH = path self

use ../../lib/matrix/check/cells.nu [check-cells-runnable summarize-gated-cells]
use ../../lib/matrix/cells.nu [expand-matrix-cells]
use ../../lib/matrix/gated-cells.nu [gate-cells-by-capabilities]
use ../../lib/tests/assert.nu *
use ../../lib/tests/fixtures.nu [with-tmp-dir materialize-provenance-stubs]
use ../../lib/tests/runner.nu [run-suite]

def repo-root [] {
    $SUITE_PATH | path dirname | path dirname | path dirname | path dirname
}

def ocmts-script [] {
    (repo-root) | path join "scripts/ocmts.nu"
}

def write-cap-gating-fixture [tmp_root: string] {
    materialize-provenance-stubs $tmp_root

    ({
        platforms: {
            nextcloud: {version_lines: ["v34"]},
            opencloud: {version_lines: ["v6"]},
        },
    } | to nuon)
    | save --force ($tmp_root | path join "config/matrix/platforms.nuon")

    ({
        schema_version: 1,
        flow_id: "login",
        label: "Login",
        subtitle: "Login flow",
        glyph_id: "key",
        display_order: 10,
        enabled: true,
        two_party: false,
        mitm: false,
        browsers: null,
        required_capabilities: {sender: ["flow.login.sender"], receiver: []},
        include: {senders: ["nextcloud" "opencloud"]},
        versions_sender: {nextcloud: ["v34"], opencloud: ["v6"]},
    } | to nuon)
    | save --force ($tmp_root | path join "config/matrix/flows/login.nuon")

    ({
        schema_version: 1,
        capabilities: ["flow.login.sender"],
    } | to nuon)
    | save --force ($tmp_root | path join "config/matrix/capabilities.v1.nuon")

    ({
        schema_version: 1,
        adapters: {
            "nextcloud/v34": {
                capabilities: {
                    "flow.login.sender": {status: "supported"},
                },
            },
            "opencloud/v6": {
                capabilities: {
                    "flow.login.sender": {status: "vendor-unsupported"},
                },
            },
        },
    } | to nuon)
    | save --force ($tmp_root | path join "config/adapters/capabilities.v1.nuon")
}

def test-matrix-check-cells-passes-on-repo [] {
    test-log "\n[test-matrix-check-cells-passes-on-repo]"
    let out = (with-env {OCMTS_ROOT: (repo-root)} {
        ^nu (ocmts-script) matrix check cells | complete
    })
    [
        (assert-eq $out.exit_code 0
            "ocmts matrix check cells exits 0 on committed matrix config")
        (assert-string-contains $out.stdout "OK"
            "ocmts matrix check cells reports OK")
    ]
}

def test-check-cells-runnable-reports-unsupported-enabled-cell [] {
    test-log "\n[test-check-cells-runnable-reports-unsupported-enabled-cell]"
    with-tmp-dir {|tmp|
        write-cap-gating-fixture $tmp
        let result = (check-cells-runnable $tmp)
        [
            (assert-truthy (($result.divergent | length) > 0)
                "enabled non-run cell appears in divergent partition")
            (assert-truthy (($result.excluded | length) > 0)
                "vendor-unsupported enabled cell appears in excluded partition")
            (assert-truthy (
                ($result.excluded | any {|e|
                    ($e.flow_id == "login") and ($e.capability_status == "vendor-unsupported")
                })
            ) "excluded entry names login flow and vendor-unsupported status")
            (assert-truthy $result.ok
                "exclude-placeholder cells are informational and do not fail ok")
        ]
    }
}

def test-summarize-gated-cells-fails-on-unknown-action-disabled [] {
    test-log "\n[test-summarize-gated-cells-fails-on-unknown-action-disabled]"
    let gated = [
        {
            enabled: false,
            cell_id: "login__opencloud-v6",
            flow_id: "login",
            capability_action: "blocked",
            capability_status: "placeholder",
        },
    ]
    let result = (summarize-gated-cells $gated)
    [
        (assert-truthy (not $result.ok)
            "unknown action on disabled cell yields ok false")
        (assert-truthy (($result.divergent | is-empty))
            "disabled cell with unknown action is not listed in divergent")
    ]
}

def test-summarize-gated-cells-fails-on-unknown-action [] {
    test-log "\n[test-summarize-gated-cells-fails-on-unknown-action]"
    let gated = [
        {
            enabled: true,
            cell_id: "login__opencloud-v6",
            flow_id: "login",
            capability_action: "blocked",
            capability_status: "vendor-unsupported",
        },
    ]
    let result = (summarize-gated-cells $gated)
    [
        (assert-truthy (not $result.ok)
            "unknown enabled non-run action yields ok false")
        (assert-truthy (($result.divergent | length) > 0)
            "unknown enabled non-run action appears in divergent")
    ]
}

def test-check-cells-runnable-partitions-cap-skipped [] {
    test-log "\n[test-check-cells-runnable-partitions-cap-skipped]"
    let rules = {
        matrix: {
            login__opencloud: {
                enabled: true,
                flow_id: "login",
                browsers: ["chrome"],
                sender: {platform: "opencloud", version_lines: ["v6"]},
                receiver: null,
                mitm: false,
            },
        },
    }
    let flow_caps = {
        login: {sender: ["flow.login.sender"], receiver: []},
    }
    let adapters = {
        "opencloud/v6": {
            capabilities: {
                "flow.login.sender": {status: "test-implementation-pending"},
            },
        },
    }
    let gated = (gate-cells-by-capabilities (expand-matrix-cells $rules) $adapters $flow_caps)
    let result = (summarize-gated-cells $gated)
    [
        (assert-truthy (($result.cap_skipped | length) > 0)
            "test-pending adapter populates cap_skipped partition")
        (assert-truthy $result.ok
            "capability-skipped cells are informational and do not fail ok")
    ]
}

def main [] {
    test-log "=== matrix/check-cells tests ==="
    let results = (
        (test-check-cells-runnable-reports-unsupported-enabled-cell)
        | append (test-summarize-gated-cells-fails-on-unknown-action)
        | append (test-summarize-gated-cells-fails-on-unknown-action-disabled)
        | append (test-check-cells-runnable-partitions-cap-skipped)
        | append (test-matrix-check-cells-passes-on-repo)
    ) | flatten
    run-suite "matrix/check-cells" $SUITE_PATH $results
}
