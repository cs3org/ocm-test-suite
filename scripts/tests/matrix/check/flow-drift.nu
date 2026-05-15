# Capability name drift check tests.
# Run: nu scripts/tests/matrix/check/flow-drift.nu
# Returns exit 0 on all pass, exit 1 with details on failure.

const SUITE_PATH = path self

use ../../../lib/matrix/check/flow-drift.nu [check-capability-name-drift validate-capability-name-shape]
use ../../../lib/tests/assert.nu *
use ../../../lib/tests/runner.nu [run-suite]
use ../../../lib/tests/fixtures.nu [with-tmp-dir]

# No unknown names when adapter_cap_keys and flow caps are all canonical.
def test-no-drift [] {
    test-log "\n[test-no-drift]"
    with-tmp-dir {|tmp|
        mkdir ($tmp | path join "config/matrix/flows")
        let flow = {flow_id: "login", required_capabilities: {sender: ["a"], receiver: []}}
        ($flow | to json) | save --force ($tmp | path join "config/matrix/flows/login.nuon")
        let result = (check-capability-name-drift $tmp ["a" "b"] ["a" "b"])
        [
            (assert-eq $result.unknown_names []
                "unknown_names is empty when all names are canonical")
        ]
    }
}

# adapter_cap_keys contains a key not in canonical.
def test-unknown-in-adapter-keys [] {
    test-log "\n[test-unknown-in-adapter-keys]"
    with-tmp-dir {|tmp|
        mkdir ($tmp | path join "config/matrix/flows")
        let flow = {flow_id: "login", required_capabilities: {sender: ["a"], receiver: []}}
        ($flow | to json) | save --force ($tmp | path join "config/matrix/flows/login.nuon")
        let result = (check-capability-name-drift $tmp ["a" "b"] ["a" "c"])
        [
            (assert-eq $result.unknown_names ["c"]
                "unknown_names contains c")
        ]
    }
}

# A flow file uses a capability not in canonical.
def test-unknown-in-flow [] {
    test-log "\n[test-unknown-in-flow]"
    with-tmp-dir {|tmp|
        mkdir ($tmp | path join "config/matrix/flows")
        let flow = {flow_id: "share-with", required_capabilities: {sender: ["a" "unknown-cap"], receiver: ["b"]}}
        ($flow | to json) | save --force ($tmp | path join "config/matrix/flows/share-with.nuon")
        let result = (check-capability-name-drift $tmp ["a" "b"] ["a" "b"])
        [
            (assert-list-contains $result.unknown_names "unknown-cap"
                "unknown-cap from flow file appears in unknown_names")
        ]
    }
}

# Empty flows dir and adapter_cap_keys are all canonical -> no drift.
def test-empty-flows [] {
    test-log "\n[test-empty-flows]"
    with-tmp-dir {|tmp|
        mkdir ($tmp | path join "config/matrix/flows")
        let result = (check-capability-name-drift $tmp ["a" "b"] ["a"])
        [
            (assert-eq $result.unknown_names []
                "no drift when flows dir is empty and adapter keys are canonical")
        ]
    }
}

# validate-capability-name-shape: roleless allowlist exceptions pass.
def test-roleless-exceptions-pass [] {
    test-log "\n[test-roleless-exceptions-pass]"
    [
        (assert-eq (validate-capability-name-shape "flow.login") null "flow.login is allowed roleless")
        (assert-eq (validate-capability-name-shape "op.login") null "op.login is allowed roleless")
        (assert-eq (validate-capability-name-shape "op.provider-identity") null "op.provider-identity is allowed roleless")
    ]
}

# validate-capability-name-shape: role-qualified names pass.
def test-role-qualified-pass [] {
    test-log "\n[test-role-qualified-pass]"
    [
        (assert-eq (validate-capability-name-shape "flow.share-with.sender") null "flow.share-with.sender is valid")
        (assert-eq (validate-capability-name-shape "op.share-file.receiver") null "op.share-file.receiver is valid")
    ]
}

# validate-capability-name-shape: unknown roleless fails.
def test-unknown-roleless-fails [] {
    test-log "\n[test-unknown-roleless-fails]"
    let err = (validate-capability-name-shape "op.foo")
    [
        (assert-eq (($err | describe) == "string") true "error message is a string for op.foo")
        (assert-eq ($err | str contains "op.foo") true "error contains the capability name")
        (assert-eq ($err | str contains "allowed roleless exceptions") true "error lists the exceptions")
    ]
}

def main [] {
    test-log "=== matrix/check/flow-drift Tests ==="
    let results = ([]
        | append (test-no-drift)
        | append (test-unknown-in-adapter-keys)
        | append (test-unknown-in-flow)
        | append (test-empty-flows)
        | append (test-roleless-exceptions-pass)
        | append (test-role-qualified-pass)
        | append (test-unknown-roleless-fails)
    )
    run-suite "matrix/check/flow-drift" $SUITE_PATH $results
}
