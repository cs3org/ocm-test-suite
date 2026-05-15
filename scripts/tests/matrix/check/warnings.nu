# Status-specific warnings tests.
# Run: nu scripts/tests/matrix/check/warnings.nu
# Returns exit 0 on all pass, exit 1 with details on failure.

const SUITE_PATH = path self

use ../../../lib/matrix/check/warnings.nu [collect-status-warnings]
use ../../../lib/tests/assert.nu *
use ../../../lib/tests/runner.nu [run-suite]

# No warnings when all entries have tracking info or are supported.
def test-no-warnings-for-supported [] {
    test-log "\n[test-no-warnings-for-supported]"
    let adapters = {
        "nextcloud/v32": {capabilities: {
            "op.login": {status: "supported"},
            "flow.share-with.sender": {status: "supported"},
        }},
    }
    let warnings = (collect-status-warnings $adapters)
    [
        (assert-eq $warnings []
            "no warnings for supported entries with no missing fields")
    ]
}

# test-implementation-pending with tracking_note: no warning.
def test-pending-with-tracking-note-ok [] {
    test-log "\n[test-pending-with-tracking-note-ok]"
    let adapters = {
        "nextcloud/v32": {capabilities: {
            "flow.code-flow.sender": {status: "test-implementation-pending", tracking_note: "tracked"},
        }},
    }
    let warnings = (collect-status-warnings $adapters)
    [
        (assert-eq $warnings []
            "no warning when tracking_note is present")
    ]
}

# test-implementation-pending with tracking_url: no warning.
def test-pending-with-tracking-url-ok [] {
    test-log "\n[test-pending-with-tracking-url-ok]"
    let adapters = {
        "nextcloud/v32": {capabilities: {
            "flow.code-flow.sender": {status: "test-implementation-pending", tracking_url: "https://example.com/123"},
        }},
    }
    let warnings = (collect-status-warnings $adapters)
    [
        (assert-eq $warnings []
            "no warning when tracking_url is present")
    ]
}

# test-implementation-pending without tracking -> warning emitted.
def test-pending-no-tracking-warns [] {
    test-log "\n[test-pending-no-tracking-warns]"
    let adapters = {
        "nextcloud/v32": {capabilities: {
            "flow.code-flow.sender": {status: "test-implementation-pending"},
        }},
    }
    let warnings = (collect-status-warnings $adapters)
    [
        (assert-truthy (($warnings | length) == 1)
            "exactly one warning")
        (assert-truthy ($warnings | any {|w| $w.message | str contains "nextcloud/v32"})
            "warning message names the adapter")
        (assert-truthy ($warnings | any {|w| $w.message | str contains "flow.code-flow.sender"})
            "warning message names the capability")
    ]
}

# vendor-unsupported without tracking -> warning.
def test-vendor-unsupported-no-tracking-warns [] {
    test-log "\n[test-vendor-unsupported-no-tracking-warns]"
    let adapters = {
        "ocmgo/v1": {capabilities: {
            "op.contact-wayf.sender": {status: "vendor-unsupported"},
        }},
    }
    let warnings = (collect-status-warnings $adapters)
    [
        (assert-truthy (($warnings | length) == 1)
            "exactly one warning for vendor-unsupported without tracking")
    ]
}

# vendor-out-of-scope without rationale -> warning.
def test-out-of-scope-no-rationale-warns [] {
    test-log "\n[test-out-of-scope-no-rationale-warns]"
    let adapters = {
        "ocmgo/v1": {capabilities: {
            "op.contact-wayf.sender": {status: "vendor-out-of-scope"},
        }},
    }
    let warnings = (collect-status-warnings $adapters)
    [
        (assert-truthy (($warnings | length) == 1)
            "exactly one warning for vendor-out-of-scope without rationale")
        (assert-truthy ($warnings | any {|w| $w.message | str contains "vendor-out-of-scope"})
            "warning message names the status")
    ]
}

# vendor-out-of-scope with rationale: no warning.
def test-out-of-scope-with-rationale-ok [] {
    test-log "\n[test-out-of-scope-with-rationale-ok]"
    let adapters = {
        "ocmgo/v1": {capabilities: {
            "op.contact-wayf.sender": {status: "vendor-out-of-scope", rationale: "Feature not relevant for this platform"},
        }},
    }
    let warnings = (collect-status-warnings $adapters)
    [
        (assert-eq $warnings []
            "no warning when rationale is present for vendor-out-of-scope")
    ]
}

# Unrecognized non-supported status without tracking_note or rationale -> warning.
def test-unknown-status-no-note-or-rationale-warns [] {
    test-log "\n[test-unknown-status-no-note-or-rationale-warns]"
    let adapters = {
        "nextcloud/v32": {capabilities: {
            "flow.future-flow.sender": {status: "experimental"},
        }},
    }
    let warnings = (collect-status-warnings $adapters)
    [
        (assert-truthy (($warnings | length) == 1)
            "exactly one warning for unknown status with no tracking_note or rationale")
        (assert-truthy ($warnings | any {|w| $w.message | str contains "experimental"})
            "warning message names the status")
        (assert-truthy ($warnings | any {|w| $w.message | str contains "flow.future-flow.sender"})
            "warning message names the capability")
    ]
}

# Unrecognized non-supported status with rationale: no warning.
def test-unknown-status-with-rationale-ok [] {
    test-log "\n[test-unknown-status-with-rationale-ok]"
    let adapters = {
        "nextcloud/v32": {capabilities: {
            "flow.future-flow.sender": {status: "experimental", rationale: "Early preview only"},
        }},
    }
    let warnings = (collect-status-warnings $adapters)
    [
        (assert-eq $warnings []
            "no warning when rationale is present for unknown non-supported status")
    ]
}

def main [] {
    test-log "=== matrix/check/warnings Tests ==="
    let results = ([]
        | append (test-no-warnings-for-supported)
        | append (test-pending-with-tracking-note-ok)
        | append (test-pending-with-tracking-url-ok)
        | append (test-pending-no-tracking-warns)
        | append (test-vendor-unsupported-no-tracking-warns)
        | append (test-out-of-scope-no-rationale-warns)
        | append (test-out-of-scope-with-rationale-ok)
        | append (test-unknown-status-no-note-or-rationale-warns)
        | append (test-unknown-status-with-rationale-ok)
    )
    run-suite "matrix/check/warnings" $SUITE_PATH $results
}
