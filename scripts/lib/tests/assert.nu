# Shared assertion helpers for ocmts internal Nushell unit-test suites.
# Used by tests under scripts/tests/. Not for Cypress E2E tests
# (those live in cypress/ and run via `ocmts test cypress ...`).
# Each helper prints a one-line ok/FAIL marker and returns the marker
# string for collection by `run-suite`. Markers: "PASS" on success,
# "FAIL: <label>" on failure. In JSON mode (OCMTS_TEST_JSON=1), all
# print calls are suppressed so stdout carries only the single JSON
# object emitted by run-suite.

export def PASS []: nothing -> string { "PASS" }
export def FAIL [msg: string]: nothing -> string { $"FAIL: ($msg)" }

# Print msg only in human mode; no-op when OCMTS_TEST_JSON=1.
export def test-log [msg: string]: nothing -> nothing {
    if ($env.OCMTS_TEST_JSON? != "1") { print $msg }
}

export def assert-eq [got: any, want: any, label: string] {
    if $got == $want {
        if ($env.OCMTS_TEST_JSON? != "1") { print $"  ok: ($label)" }
        PASS
    } else {
        if ($env.OCMTS_TEST_JSON? != "1") {
            print $"  FAIL: ($label)"
            print $"    got:  ($got | to json)"
            print $"    want: ($want | to json)"
        }
        FAIL $label
    }
}

export def assert-truthy [got: bool, label: string] {
    if $got {
        if ($env.OCMTS_TEST_JSON? != "1") { print $"  ok: ($label)" }
        PASS
    } else {
        if ($env.OCMTS_TEST_JSON? != "1") { print $"  FAIL: ($label) - expected truthy" }
        FAIL $label
    }
}

export def assert-null [got: any, label: string] {
    if $got == null {
        if ($env.OCMTS_TEST_JSON? != "1") { print $"  ok: ($label)" }
        PASS
    } else {
        if ($env.OCMTS_TEST_JSON? != "1") {
            print $"  FAIL: ($label) - expected null"
            print $"    got: ($got | to json)"
        }
        FAIL $label
    }
}

export def assert-not-null [got: any, label: string] {
    if $got != null {
        if ($env.OCMTS_TEST_JSON? != "1") { print $"  ok: ($label)" }
        PASS
    } else {
        if ($env.OCMTS_TEST_JSON? != "1") { print $"  FAIL: ($label) - expected non-null, got null" }
        FAIL $label
    }
}

export def assert-string-contains [got: string, sub: string, label: string] {
    if ($got | str contains $sub) {
        if ($env.OCMTS_TEST_JSON? != "1") { print $"  ok: ($label)" }
        PASS
    } else {
        if ($env.OCMTS_TEST_JSON? != "1") {
            print $"  FAIL: ($label)"
            print $"    string ($got | to json) does not contain ($sub | to json)"
        }
        FAIL $label
    }
}

export def assert-list-contains [got: list, item: any, label: string] {
    if ($item in $got) {
        if ($env.OCMTS_TEST_JSON? != "1") { print $"  ok: ($label)" }
        PASS
    } else {
        if ($env.OCMTS_TEST_JSON? != "1") {
            print $"  FAIL: ($label)"
            print $"    item ($item | to json) not in ($got | to json)"
        }
        FAIL $label
    }
}

export def assert-list-not-contains [got: list, item: any, label: string] {
    if not ($item in $got) {
        if ($env.OCMTS_TEST_JSON? != "1") { print $"  ok: ($label)" }
        PASS
    } else {
        if ($env.OCMTS_TEST_JSON? != "1") {
            print $"  FAIL: ($label)"
            print $"    unexpected item ($item | to json) found in ($got | to json)"
        }
        FAIL $label
    }
}
