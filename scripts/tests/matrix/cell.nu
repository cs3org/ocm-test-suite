# Matrix cell validation tests.
# Run: nu scripts/tests/matrix/cell.nu

const SUITE_PATH = path self

use ../../lib/matrix/cell.nu [assert-matrix-entry-enabled validate-cell-rules]
use ../../lib/tests/assert.nu *
use ../../lib/tests/runner.nu [run-suite]
use ../../lib/tests/fixtures.nu [with-tmp-dir]

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
        mitm: false
        browsers: ["chrome"]
        required_capabilities: {sender: [], receiver: []}
        include: [{sender: ["nextcloud"], receiver: ["ocmgo"]}]
        versions_sender: {nextcloud: ["v32"]}
        versions_receiver: {ocmgo: ["v1"]}
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

def test-assert-enabled-allows-known-enabled-entry [] {
    test-log "\n[test-assert-enabled-allows-known-enabled-entry]"
    with-tmp-dir {|tmp|
        write-matrix-fixture $tmp
        with-env {OCMTS_ROOT: $tmp} {
            let result = (
                try { assert-matrix-entry-enabled "login" "nextcloud" ""; "ok" }
                catch {|e| $"error: ($e.msg)"}
            )
            [
                (assert-eq $result "ok"
                    "enabled matrix entry passes assert-matrix-entry-enabled")
            ]
        }
    }
}

def test-assert-enabled-rejects-absent-entry [] {
    test-log "\n[test-assert-enabled-rejects-absent-entry]"
    with-tmp-dir {|tmp|
        write-matrix-fixture $tmp
        with-env {OCMTS_ROOT: $tmp} {
            let result = (
                try { assert-matrix-entry-enabled "login" "ocmgo" ""; "ok" }
                catch {|e| $"error: ($e.msg)"}
            )
            [
                (assert-truthy ($result | str starts-with "error:")
                    "absent matrix entry errors")
                (assert-string-contains $result "not in config/matrix"
                    "absent matrix entry error names config/matrix")
            ]
        }
    }
}

def test-assert-enabled-rejects-disabled-entry [] {
    test-log "\n[test-assert-enabled-rejects-disabled-entry]"
    with-tmp-dir {|tmp|
        write-matrix-fixture $tmp
        with-env {OCMTS_ROOT: $tmp} {
            let result = (
                try {
                    assert-matrix-entry-enabled "contact-wayf" "nextcloud" "ocmgo"
                    "ok"
                } catch {|e| $"error: ($e.msg)"}
            )
            [
                (assert-truthy ($result | str starts-with "error:")
                    "disabled matrix entry errors")
                (assert-string-contains $result "disabled"
                    "disabled matrix entry error names disabled status")
                (assert-string-contains $result "contact-wayf__nextcloud__ocmgo"
                    "disabled matrix entry error names matrix_key")
            ]
        }
    }
}

def test-validate-cell-rules-one-party-ok [] {
    test-log "\n[test-validate-cell-rules-one-party-ok]"
    with-tmp-dir {|tmp|
        write-matrix-fixture $tmp
        with-env {OCMTS_ROOT: $tmp} {
            let result = (
                try { validate-cell-rules "login" "nextcloud" "v32" "chrome" "" }
                catch {|e| $"error: ($e.msg)"}
            )
            [
                (assert-eq $result "login"
                    "validate-cell-rules returns canonical one-party flow_id")
            ]
        }
    }
}

def test-validate-cell-rules-two-party-ok [] {
    test-log "\n[test-validate-cell-rules-two-party-ok]"
    with-tmp-dir {|tmp|
        write-matrix-fixture $tmp
        with-env {OCMTS_ROOT: $tmp} {
            let result = (
                try {
                    validate-cell-rules "share-with" "nextcloud" "v32" "chrome" "ocmgo" "v1"
                } catch {|e| $"error: ($e.msg)"}
            )
            [
                (assert-eq $result "share-with"
                    "validate-cell-rules returns canonical two-party flow_id")
            ]
        }
    }
}

def test-assert-enabled-rejects-missing-receiver-on-two-party [] {
    test-log "\n[test-assert-enabled-rejects-missing-receiver-on-two-party]"
    with-tmp-dir {|tmp|
        write-matrix-fixture $tmp
        with-env {OCMTS_ROOT: $tmp} {
            let result = (
                try { assert-matrix-entry-enabled "share-with" "nextcloud" ""; "ok" }
                catch {|e| $"error: ($e.msg)"}
            )
            [
                (assert-truthy ($result | str starts-with "error:")
                    "two-party assert without receiver errors")
                (assert-string-contains $result "requires --receiver-platform"
                    "missing receiver error names --receiver-platform")
                (assert-string-contains $result "share-with"
                    "missing receiver error names flow")
                (assert-truthy (not ($result | str contains "not in config/matrix"))
                    "missing receiver does not report absent-in-matrix")
            ]
        }
    }
}

def test-validate-cell-rules-rejects-invalid-browser [] {
    test-log "\n[test-validate-cell-rules-rejects-invalid-browser]"
    with-tmp-dir {|tmp|
        write-matrix-fixture $tmp
        with-env {OCMTS_ROOT: $tmp} {
            let result = (
                try { validate-cell-rules "login" "nextcloud" "v32" "firefox" ""; "ok" }
                catch {|e| $"error: ($e.msg)"}
            )
            [
                (assert-truthy ($result | str starts-with "error:")
                    "invalid browser errors")
                (assert-string-contains $result "Browser 'firefox'"
                    "invalid browser error names the browser")
                (assert-string-contains $result "login__nextcloud"
                    "invalid browser error names matrix entry")
            ]
        }
    }
}

def test-validate-cell-rules-rejects-bad-sender-version [] {
    test-log "\n[test-validate-cell-rules-rejects-bad-sender-version]"
    with-tmp-dir {|tmp|
        write-matrix-fixture $tmp
        with-env {OCMTS_ROOT: $tmp} {
            let result = (
                try { validate-cell-rules "login" "nextcloud" "v99" "chrome" ""; "ok" }
                catch {|e| $"error: ($e.msg)"}
            )
            [
                (assert-truthy ($result | str starts-with "error:")
                    "bad sender version errors")
                (assert-string-contains $result "Sender version 'v99'"
                    "bad sender version error names the version")
            ]
        }
    }
}

def test-validate-cell-rules-rejects-bad-receiver-version [] {
    test-log "\n[test-validate-cell-rules-rejects-bad-receiver-version]"
    with-tmp-dir {|tmp|
        write-matrix-fixture $tmp
        with-env {OCMTS_ROOT: $tmp} {
            let result = (
                try {
                    validate-cell-rules "share-with" "nextcloud" "v32" "chrome" "ocmgo" "v99"
                    "ok"
                } catch {|e| $"error: ($e.msg)"}
            )
            [
                (assert-truthy ($result | str starts-with "error:")
                    "bad receiver version errors")
                (assert-string-contains $result "Receiver version 'v99'"
                    "bad receiver version error names the version")
            ]
        }
    }
}

def test-validate-cell-rules-rejects-spurious-receiver-on-one-party [] {
    test-log "\n[test-validate-cell-rules-rejects-spurious-receiver-on-one-party]"
    with-tmp-dir {|tmp|
        write-matrix-fixture $tmp
        with-env {OCMTS_ROOT: $tmp} {
            let platform_result = (
                try { validate-cell-rules "login" "nextcloud" "v32" "chrome" "ocmgo" ""; "ok" }
                catch {|e| $"error: ($e.msg)"}
            )
            let version_result = (
                try { validate-cell-rules "login" "nextcloud" "v32" "chrome" "" "v1"; "ok" }
                catch {|e| $"error: ($e.msg)"}
            )
            [
                (assert-truthy ($platform_result | str starts-with "error:")
                    "one-party validate with receiver platform errors")
                (assert-string-contains $platform_result "one-party"
                    "spurious receiver platform error names one-party")
                (assert-string-contains $platform_result "--receiver-platform"
                    "spurious receiver platform error names --receiver-platform")
                (assert-truthy ($version_result | str starts-with "error:")
                    "one-party validate with receiver version errors")
                (assert-string-contains $version_result "--receiver-version"
                    "spurious receiver version error names --receiver-version")
            ]
        }
    }
}

def test-validate-cell-rules-rejects-missing-receiver-on-two-party [] {
    test-log "\n[test-validate-cell-rules-rejects-missing-receiver-on-two-party]"
    with-tmp-dir {|tmp|
        write-matrix-fixture $tmp
        with-env {OCMTS_ROOT: $tmp} {
            let result = (
                try { validate-cell-rules "share-with" "nextcloud" "v32" "chrome" ""; "ok" }
                catch {|e| $"error: ($e.msg)"}
            )
            [
                (assert-truthy ($result | str starts-with "error:")
                    "two-party validate without receiver errors")
                (assert-string-contains $result "requires --receiver-platform"
                    "missing receiver error names --receiver-platform")
                (assert-string-contains $result "share-with"
                    "missing receiver error names flow")
                (assert-truthy (not ($result | str contains "not in config/matrix"))
                    "missing receiver does not report absent-in-matrix")
            ]
        }
    }
}

def test-validate-cell-rules-rejects-explicit-pairs-mismatch [] {
    test-log "\n[test-validate-cell-rules-rejects-explicit-pairs-mismatch]"
    with-tmp-dir {|tmp|
        mkdir ($tmp | path join "config/matrix/flows")
        ({browsers_default: ["chrome"]} | to nuon)
        | save --force ($tmp | path join "config/matrix/defaults.nuon")
        ({
            schema_version: 1
            platforms: {
                nextcloud: {version_lines: ["v32", "v33"]}
                ocmgo: {version_lines: ["v1"]}
            }
        } | to nuon)
        | save --force ($tmp | path join "config/matrix/platforms.nuon")
        ({
            schema_version: 1
            flow_id: "contact-wayf"
            two_party: true
            enabled: true
            mitm: true
            browsers: ["chrome"]
            required_capabilities: {sender: [], receiver: []}
            include: [{
                sender: ["nextcloud"]
                receiver: ["ocmgo"]
                version_pairing: "explicit_pairs"
                version_pairs: [{sender: "v32", receiver: "v1"}]
            }]
            versions_sender: {nextcloud: ["v32", "v33"]}
            versions_receiver: {ocmgo: ["v1"]}
        } | to nuon)
        | save --force ($tmp | path join "config/matrix/flows/contact-wayf.nuon")
        with-env {OCMTS_ROOT: $tmp} {
            let ok = (
                try {
                    validate-cell-rules "contact-wayf" "nextcloud" "v32" "chrome" "ocmgo" "v1"
                } catch {|e| $"error: ($e.msg)"}
            )
            let bad = (
                try {
                    validate-cell-rules "contact-wayf" "nextcloud" "v33" "chrome" "ocmgo" "v1"
                    "ok"
                } catch {|e| $"error: ($e.msg)"}
            )
            [
                (assert-eq $ok "contact-wayf"
                    "explicit_pairs allowed sender/receiver version pair passes")
                (assert-truthy ($bad | str starts-with "error:")
                    "explicit_pairs rejected version pair errors")
                (assert-string-contains $bad "explicit_pairs"
                    "rejected pair error names explicit_pairs policy")
                (assert-string-contains $bad "contact-wayf__nextcloud__ocmgo"
                    "rejected pair error names matrix entry")
            ]
        }
    }
}

def test-validate-cell-rules-rejects-disabled-entry [] {
    test-log "\n[test-validate-cell-rules-rejects-disabled-entry]"
    with-tmp-dir {|tmp|
        write-matrix-fixture $tmp
        with-env {OCMTS_ROOT: $tmp} {
            let result = (
                try {
                    validate-cell-rules "contact-wayf" "nextcloud" "v32" "chrome" "ocmgo" "v1"
                    "ok"
                } catch {|e| $"error: ($e.msg)"}
            )
            [
                (assert-truthy ($result | str starts-with "error:")
                    "validate-cell-rules disabled entry errors")
                (assert-string-contains $result "disabled"
                    "validate-cell-rules disabled entry error names disabled status")
                (assert-string-contains $result "contact-wayf__nextcloud__ocmgo"
                    "validate-cell-rules disabled entry error names matrix_key")
            ]
        }
    }
}

def test-validate-cell-rules-rejects-absent-entry [] {
    test-log "\n[test-validate-cell-rules-rejects-absent-entry]"
    with-tmp-dir {|tmp|
        write-matrix-fixture $tmp
        with-env {OCMTS_ROOT: $tmp} {
            let result = (
                try { validate-cell-rules "share-with" "nextcloud" "v32" "chrome" "nextcloud" "v1"; "ok" }
                catch {|e| $"error: ($e.msg)"}
            )
            [
                (assert-truthy ($result | str starts-with "error:")
                    "validate-cell-rules absent entry errors")
                (assert-string-contains $result "not in config/matrix"
                    "validate-cell-rules absent entry error names config/matrix")
            ]
        }
    }
}

def test-assert-enabled-rejects-malformed-tuple [] {
    test-log "\n[test-assert-enabled-rejects-malformed-tuple]"
    with-tmp-dir {|tmp|
        write-matrix-fixture $tmp
        with-env {OCMTS_ROOT: $tmp} {
            let result = (
                try { assert-matrix-entry-enabled "login" "" ""; "ok" }
                catch {|e| $"error: ($e.msg)"}
            )
            [
                (assert-truthy ($result | str starts-with "error:")
                    "empty sender segment errors before matrix lookup")
                (assert-string-contains $result "sender_platform must not be empty"
                    "empty sender error names sender_platform validation")
            ]
        }
    }
}

def test-validate-cell-rules-rejects-malformed-tuple [] {
    test-log "\n[test-validate-cell-rules-rejects-malformed-tuple]"
    with-tmp-dir {|tmp|
        write-matrix-fixture $tmp
        with-env {OCMTS_ROOT: $tmp} {
            let result = (
                try {
                    validate-cell-rules "login" "Bad_Platform" "v32" "chrome" ""
                    "ok"
                } catch {|e| $"error: ($e.msg)"}
            )
            [
                (assert-truthy ($result | str starts-with "error:")
                    "invalid sender platform shape errors before matrix lookup")
                (assert-string-contains $result "sender_platform shape invalid"
                    "malformed tuple error names sender_platform validation")
            ]
        }
    }
}

def test-assert-enabled-rejects-path-traversal-flow-id [] {
    test-log "\n[test-assert-enabled-rejects-path-traversal-flow-id]"
    with-tmp-dir {|tmp|
        write-matrix-fixture $tmp
        with-env {OCMTS_ROOT: $tmp} {
            let result = (
                try { assert-matrix-entry-enabled "../../../etc/passwd" "nextcloud" ""; "ok" }
                catch {|e| $"error: ($e.msg)"}
            )
            [
                (assert-truthy ($result | str starts-with "error:")
                    "path traversal flow_id errors before filesystem lookup")
                (assert-string-contains $result "flow_id"
                    "path traversal flow_id error names flow_id validation")
            ]
        }
    }
}

def test-validate-cell-rules-rejects-path-traversal-flow-id [] {
    test-log "\n[test-validate-cell-rules-rejects-path-traversal-flow-id]"
    with-tmp-dir {|tmp|
        write-matrix-fixture $tmp
        with-env {OCMTS_ROOT: $tmp} {
            let result = (
                try {
                    validate-cell-rules "../../../etc/passwd" "nextcloud" "v32" "chrome" ""
                    "ok"
                } catch {|e| $"error: ($e.msg)"}
            )
            [
                (assert-truthy ($result | str starts-with "error:")
                    "path traversal flow_id errors before filesystem lookup")
                (assert-string-contains $result "flow_id"
                    "path traversal flow_id error names flow_id validation")
            ]
        }
    }
}

def main [] {
    test-log "=== matrix/cell tests ==="
    let results = (
        (test-assert-enabled-allows-known-enabled-entry)
        | append (test-assert-enabled-rejects-absent-entry)
        | append (test-assert-enabled-rejects-disabled-entry)
        | append (test-assert-enabled-rejects-missing-receiver-on-two-party)
        | append (test-assert-enabled-rejects-malformed-tuple)
        | append (test-validate-cell-rules-one-party-ok)
        | append (test-validate-cell-rules-two-party-ok)
        | append (test-validate-cell-rules-rejects-invalid-browser)
        | append (test-validate-cell-rules-rejects-bad-sender-version)
        | append (test-validate-cell-rules-rejects-bad-receiver-version)
        | append (test-validate-cell-rules-rejects-missing-receiver-on-two-party)
        | append (test-validate-cell-rules-rejects-spurious-receiver-on-one-party)
        | append (test-validate-cell-rules-rejects-explicit-pairs-mismatch)
        | append (test-validate-cell-rules-rejects-absent-entry)
        | append (test-validate-cell-rules-rejects-disabled-entry)
        | append (test-validate-cell-rules-rejects-malformed-tuple)
        | append (test-assert-enabled-rejects-path-traversal-flow-id)
        | append (test-validate-cell-rules-rejects-path-traversal-flow-id)
    ) | flatten
    run-suite "matrix/cell" $SUITE_PATH $results
}
