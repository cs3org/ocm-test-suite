# Unit tests for the gated-cells capability gating helper.
# Run: nu scripts/tests/matrix/gated-cells.nu
# Returns exit 0 on all pass, exit 1 with details on failure.

const SUITE_PATH = path self

use ../../lib/matrix/gated-cells.nu [
    gate-one-cell
    gate-cells-by-capabilities
    runnable-cells
    capability-skipped-cells
]
use ../../lib/tests/assert.nu *
use ../../lib/tests/runner.nu [run-suite]

# Adapters with supported capabilities only.
def adapters-all-supported [] {
    {
        "nextcloud/v34": {
            capabilities: {
                "op.login": {status: "supported"},
                "flow.share-with.sender": {status: "supported"},
                "flow.share-with.receiver": {status: "supported"},
            }
        }
    }
}

# Adapters where nextcloud/v34 has test-implementation-pending for one cap.
def adapters-test-pending [] {
    {
        "opencloud/v6": {
            capabilities: {
                "op.login": {status: "supported"},
                "flow.share-with.sender": {status: "test-implementation-pending"},
                "flow.share-with.receiver": {status: "test-implementation-pending"},
            }
        }
    }
}

# Adapters where a platform is vendor-unsupported for a cap.
def adapters-vendor-unsupported [] {
    {
        "nextcloud/v32": {
            capabilities: {
                "op.login": {status: "supported"},
                "flow.share-with.sender": {status: "vendor-unsupported"},
            }
        }
    }
}

# Adapters where a platform is vendor-out-of-scope.
def adapters-vendor-oos [] {
    {
        "seafile/v1": {
            capabilities: {
                "op.login": {status: "supported"},
                "flow.code-flow.sender": {
                    status: "vendor-out-of-scope",
                    rationale: "seafile does not implement code-flow",
                },
            }
        }
    }
}

def flow-caps-share-with [] {
    {
        "share-with": {
            sender: ["flow.share-with.sender"],
            receiver: ["flow.share-with.receiver"],
        }
    }
}

def flow-caps-code-flow [] {
    {
        "code-flow": {
            sender: ["flow.code-flow.sender"],
            receiver: [],
        }
    }
}

def make-cell [flow_id: string, platform: string, version: string, --enabled = true] {
    {
        cell_id: $"($flow_id)__($platform)-($version)",
        flow_id: $flow_id,
        matrix_key: $flow_id,
        sender_platform: $platform,
        sender_version: $version,
        receiver_platform: "",
        receiver_version: "",
        is_two_party: false,
        enabled: $enabled,
        browser: "chrome",
    }
}

def test-supported-cell [] {
    test-log "\n[test-supported-cell]"
    let cell = (make-cell "share-with" "nextcloud" "v34")
    let adapters = {
        "nextcloud/v34": {
            capabilities: {
                "flow.share-with.sender": {status: "supported"},
                "flow.share-with.receiver": {status: "supported"},
            }
        }
    }
    let g = (gate-one-cell $cell $adapters (flow-caps-share-with))
    [
        (assert-eq $g.capability_status "supported" "supported: capability_status")
        (assert-eq $g.capability_action "run" "supported: capability_action")
        (assert-truthy $g.display_visible "supported: display_visible true")
        (assert-eq $g.display_status "supported" "supported: display_status")
    ]
}

def test-test-pending-cell [] {
    test-log "\n[test-test-pending-cell]"
    let cell = (make-cell "share-with" "opencloud" "v6")
    let g = (gate-one-cell $cell (adapters-test-pending) (flow-caps-share-with))
    [
        (assert-eq $g.capability_status "test-implementation-pending"
            "test-pending: capability_status")
        (assert-eq $g.capability_action "capability-skipped"
            "test-pending: capability_action")
        (assert-truthy $g.display_visible "test-pending: display_visible true")
        (assert-eq $g.display_status "test-pending" "test-pending: display_status")
    ]
}

def test-vendor-unsupported-cell [] {
    test-log "\n[test-vendor-unsupported-cell]"
    let cell = (make-cell "share-with" "nextcloud" "v32")
    let adapters = {
        "nextcloud/v32": {
            capabilities: {
                "flow.share-with.sender": {status: "vendor-unsupported"},
                "flow.share-with.receiver": {status: "supported"},
            }
        }
    }
    let g = (gate-one-cell $cell $adapters (flow-caps-share-with))
    [
        (assert-eq $g.capability_status "vendor-unsupported"
            "vendor-unsupported: capability_status")
        (assert-eq $g.capability_action "exclude-placeholder"
            "vendor-unsupported: capability_action")
        (assert-truthy $g.display_visible "vendor-unsupported: display_visible true")
        (assert-eq $g.display_status "vendor-unsupported"
            "vendor-unsupported: display_status")
    ]
}

def test-vendor-out-of-scope-cell [] {
    test-log "\n[test-vendor-out-of-scope-cell]"
    let cell = (make-cell "code-flow" "seafile" "v1")
    let g = (gate-one-cell $cell (adapters-vendor-oos) (flow-caps-code-flow))
    [
        (assert-eq $g.capability_status "vendor-out-of-scope"
            "out-of-scope: capability_status")
        (assert-eq $g.capability_action "exclude-placeholder"
            "out-of-scope: capability_action")
        (assert-truthy (not $g.display_visible) "out-of-scope: display_visible false")
        (assert-eq $g.display_status "out-of-scope" "out-of-scope: display_status")
    ]
}

def test-disabled-supported-becomes-placeholder [] {
    test-log "\n[test-disabled-supported-becomes-placeholder]"
    let cell = (make-cell "share-with" "nextcloud" "v34" --enabled false)
    let adapters = {
        "nextcloud/v34": {
            capabilities: {
                "flow.share-with.sender": {status: "supported"},
                "flow.share-with.receiver": {status: "supported"},
            }
        }
    }
    let g = (gate-one-cell $cell $adapters (flow-caps-share-with))
    [
        (assert-eq $g.capability_status "placeholder"
            "disabled+supported: capability_status becomes placeholder")
        (assert-eq $g.capability_action "exclude-placeholder"
            "disabled+supported: capability_action")
        (assert-truthy $g.display_visible "disabled+supported: display_visible true")
        (assert-eq $g.display_status "placeholder"
            "disabled+supported: display_status")
    ]
}

def test-disabled-oos-stays-oos [] {
    test-log "\n[test-disabled-oos-stays-oos]"
    let cell = (make-cell "code-flow" "seafile" "v1" --enabled false)
    let g = (gate-one-cell $cell (adapters-vendor-oos) (flow-caps-code-flow))
    [
        (assert-eq $g.capability_status "vendor-out-of-scope"
            "disabled+OOS: capability_status stays vendor-out-of-scope")
        (assert-truthy (not $g.display_visible)
            "disabled+OOS: display_visible false")
    ]
}

def test-worst-role-wins [] {
    test-log "\n[test-worst-role-wins]"
    # Two-party cell: sender supported, receiver test-pending. Worst = test-pending.
    let cell = {
        cell_id: "share-with__nextcloud-v34__opencloud-v6",
        flow_id: "share-with",
        matrix_key: "share-with__nextcloud__opencloud",
        sender_platform: "nextcloud",
        sender_version: "v34",
        receiver_platform: "opencloud",
        receiver_version: "v6",
        is_two_party: true,
        enabled: true,
        browser: "chrome",
    }
    let adapters = {
        "nextcloud/v34": {
            capabilities: {
                "flow.share-with.sender": {status: "supported"},
                "flow.share-with.receiver": {status: "supported"},
            }
        },
        "opencloud/v6": {
            capabilities: {
                "flow.share-with.sender": {status: "supported"},
                "flow.share-with.receiver": {status: "test-implementation-pending"},
            }
        },
    }
    let g = (gate-one-cell $cell $adapters (flow-caps-share-with))
    [
        (assert-eq $g.capability_status "test-implementation-pending"
            "worst role wins: test-pending from receiver dominates supported sender")
        (assert-eq $g.capability_action "capability-skipped"
            "worst role wins: capability_action is capability-skipped")
        (assert-eq $g.display_status "test-pending"
            "worst role wins: display_status is test-pending")
    ]
}

def test-runnable-cells-helper [] {
    test-log "\n[test-runnable-cells-helper]"
    let cell_run = {cell_id: "a", capability_action: "run", flow_id: "login"}
    let cell_skip = {cell_id: "b", capability_action: "capability-skipped", flow_id: "login"}
    let cell_excl = {cell_id: "c", capability_action: "exclude-placeholder", flow_id: "login"}
    let result = (runnable-cells [$cell_run $cell_skip $cell_excl])
    [
        (assert-eq ($result | length) 1 "runnable-cells: exactly 1 runnable cell")
        (assert-eq ($result | first | get cell_id) "a"
            "runnable-cells: returned cell is the run cell")
    ]
}

def test-capability-skipped-cells-helper [] {
    test-log "\n[test-capability-skipped-cells-helper]"
    let cell_run = {cell_id: "a", capability_action: "run", flow_id: "login"}
    let cell_skip = {cell_id: "b", capability_action: "capability-skipped", flow_id: "login"}
    let cell_excl = {cell_id: "c", capability_action: "exclude-placeholder", flow_id: "login"}
    let result = (capability-skipped-cells [$cell_run $cell_skip $cell_excl])
    [
        (assert-eq ($result | length) 1 "capability-skipped-cells: exactly 1 skipped cell")
        (assert-eq ($result | first | get cell_id) "b"
            "capability-skipped-cells: returned cell is the skipped cell")
    ]
}

def test-gate-cells-by-capabilities-batch [] {
    test-log "\n[test-gate-cells-by-capabilities-batch]"
    let cells = [
        (make-cell "code-flow" "seafile" "v1")
        (make-cell "share-with" "nextcloud" "v34")
    ]
    let adapters = {
        "seafile/v1": {
            capabilities: {
                "flow.code-flow.sender": {status: "vendor-out-of-scope"},
            }
        },
        "nextcloud/v34": {
            capabilities: {
                "flow.share-with.sender": {status: "supported"},
                "flow.share-with.receiver": {status: "supported"},
            }
        },
    }
    let flow_caps = {
        "code-flow": {sender: ["flow.code-flow.sender"], receiver: []},
        "share-with": {sender: ["flow.share-with.sender"], receiver: []},
    }
    let gated = (gate-cells-by-capabilities $cells $adapters $flow_caps)
    let seafile = ($gated | where {|c| $c.sender_platform == "seafile"} | first)
    let nc = ($gated | where {|c| $c.sender_platform == "nextcloud"} | first)
    [
        (assert-eq ($gated | length) 2 "gate-cells-by-capabilities: returns same count")
        (assert-truthy (not $seafile.display_visible)
            "gate-cells: seafile oos has display_visible false")
        (assert-truthy $nc.display_visible
            "gate-cells: nextcloud supported has display_visible true")
        (assert-eq $nc.capability_action "run"
            "gate-cells: nextcloud supported gets action run")
    ]
}

# An adapter capability with an unknown status string must cause gate-one-cell
# to error with a descriptive message rather than silently falling back.
def test-gate-unknown-status-errors [] {
    test-log "\n[test-gate-unknown-status-errors]"
    let cell = (make-cell "share-with" "nextcloud" "v34")
    let adapters = {
        "nextcloud/v34": {
            capabilities: {
                "flow.share-with.sender": {status: "bogus-typo"},
            }
        }
    }
    let err = (try {
        gate-one-cell $cell $adapters (flow-caps-share-with)
        ""
    } catch {|e| $e.msg})
    [
        (assert-string-contains $err "unknown capability_status"
            "error describes the problem as unknown capability_status")
        (assert-string-contains $err "bogus-typo"
            "error names the offending status value")
    ]
}

# A raw adapter capability with status "placeholder" produces the correct
# locked gate mapping without triggering the unknown-status error path.
def test-gate-raw-placeholder-status [] {
    test-log "\n[test-gate-raw-placeholder-status]"
    let cell = (make-cell "share-with" "nextcloud" "v34")
    let adapters = {
        "nextcloud/v34": {
            capabilities: {
                "flow.share-with.sender": {status: "placeholder"},
            }
        }
    }
    let g = (gate-one-cell $cell $adapters (flow-caps-share-with))
    [
        (assert-eq $g.capability_status "placeholder"
            "raw placeholder: capability_status")
        (assert-eq $g.capability_action "exclude-placeholder"
            "raw placeholder: capability_action")
        (assert-truthy $g.display_visible "raw placeholder: display_visible true")
        (assert-eq $g.display_status "placeholder"
            "raw placeholder: display_status")
    ]
}

def main [] {
    test-log "=== gated-cells tests ==="
    let results = (
        (test-supported-cell)
        | append (test-test-pending-cell)
        | append (test-vendor-unsupported-cell)
        | append (test-vendor-out-of-scope-cell)
        | append (test-disabled-supported-becomes-placeholder)
        | append (test-disabled-oos-stays-oos)
        | append (test-worst-role-wins)
        | append (test-runnable-cells-helper)
        | append (test-capability-skipped-cells-helper)
        | append (test-gate-cells-by-capabilities-batch)
        | append (test-gate-unknown-status-errors)
        | append (test-gate-raw-placeholder-status)
    ) | flatten
    run-suite "matrix/gated-cells" $SUITE_PATH $results
}
