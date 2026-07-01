# Actor validator tests.
# Run: nu scripts/tests/actors/validate.nu

const SUITE_PATH = path self

use ../../lib/actors/validate.nu [validate-actor-config]
use ../../lib/tests/assert.nu *
use ../../lib/tests/runner.nu [run-suite]
use ../../lib/tests/fixtures.nu [with-tmp-dir]

def write-minimal-fixture [tmp_root: string] {
    mkdir ($tmp_root | path join "config/matrix/flows")
    mkdir ($tmp_root | path join "config/actors/overrides")
    mkdir ($tmp_root | path join "config/actors/platforms")

    ({browsers_default: ["chromium"]} | to nuon)
    | save --force ($tmp_root | path join "config/matrix/defaults.nuon")

    ({platforms: {
        nextcloud: {version_lines: ["v32"]},
        ocmgo: {version_lines: ["v1"]}
    }} | to nuon)
    | save --force ($tmp_root | path join "config/matrix/platforms.nuon")

    ({schema_version: 1, flow_id: "login", two_party: false, enabled: true,
      mitm: false, browsers: null,
      required_capabilities: {sender: [], receiver: []},
      include: {senders: ["nextcloud"]},
      versions_sender: {nextcloud: ["v32"]}
    } | to nuon)
    | save --force ($tmp_root | path join "config/matrix/flows/login.nuon")

    ({schema_version: 1, flow_id: "share-with", two_party: true, enabled: true,
      mitm: false, browsers: null,
      required_capabilities: {sender: [], receiver: []},
      include: [{sender: ["nextcloud"], receiver: ["nextcloud"]}],
      versions_sender: {nextcloud: ["v32"]},
      versions_receiver: {nextcloud: ["v32"]}
    } | to nuon)
    | save --force ($tmp_root | path join "config/matrix/flows/share-with.nuon")

    ({schema_version: 1, flow_id: "contact-wayf", two_party: true, enabled: false,
      mitm: true, browsers: null,
      required_capabilities: {sender: [], receiver: []},
      include: [{sender: ["nextcloud"], receiver: ["ocmgo"]}],
      versions_sender: {nextcloud: ["v32"]},
      versions_receiver: {ocmgo: ["v1"]}
    } | to nuon)
    | save --force ($tmp_root | path join "config/matrix/flows/contact-wayf.nuon")

    ({flows: {
        login: {actor: {by_platform: {nextcloud: "michiel"}}},
        "share-with": {
            sender: {by_platform: {nextcloud: "michiel"}},
            receiver: {by_platform: {nextcloud: "marie"}}
        }
    }} | to nuon)
    | save --force ($tmp_root | path join "config/actors/defaults.nuon")

    ({accounts: {
        michiel: {username: "michiel_user", password: "michiel_pass"},
        marie: {username: "marie_user", password: "marie_pass"}
    }} | to nuon)
    | save --force ($tmp_root | path join "config/actors/platforms/nextcloud.nuon")
}

def test-one-party-no-override-ok [] {
    test-log "\n[test-one-party-no-override-ok]"
    with-tmp-dir {|tmp|
        write-minimal-fixture $tmp
        with-env {OCMTS_ROOT: $tmp} {
            let result = (
                try { validate-actor-config "login" $tmp "nextcloud" ""; "ok" }
                catch {|e| $"error: ($e.msg)"}
            )
            [(assert-eq $result "ok" "one-party tuple with no override file validates ok")]
        }
    }
}

def test-two-party-no-override-ok [] {
    test-log "\n[test-two-party-no-override-ok]"
    with-tmp-dir {|tmp|
        write-minimal-fixture $tmp
        with-env {OCMTS_ROOT: $tmp} {
            let result = (
                try { validate-actor-config "share-with" $tmp "nextcloud" "nextcloud"; "ok" }
                catch {|e| $"error: ($e.msg)"}
            )
            [(assert-eq $result "ok" "two-party tuple with no override file validates ok")]
        }
    }
}

def test-two-party-missing-receiver-errors-clearly [] {
    test-log "\n[test-two-party-missing-receiver-errors-clearly]"
    with-tmp-dir {|tmp|
        write-minimal-fixture $tmp
        with-env {OCMTS_ROOT: $tmp} {
            let result = (
                try { validate-actor-config "share-with" $tmp "nextcloud" ""; "ok" }
                catch {|e| $"error: ($e.msg)"}
            )
            [
                (assert-truthy ($result | str starts-with "error:")
                    "two-party tuple without receiver causes an error")
                (assert-string-contains $result "requires --receiver-platform"
                    "missing receiver error names --receiver-platform")
                (assert-string-contains $result "share-with"
                    "missing receiver error names flow")
            ]
        }
    }
}

def test-override-shape-mismatch [] {
    test-log "\n[test-override-shape-mismatch]"
    with-tmp-dir {|tmp|
        write-minimal-fixture $tmp
        ({actor: {account: "michiel"}} | to nuon)
        | save --force ($tmp | path join "config/actors/overrides/share-with__nextcloud__nextcloud.nuon")
        with-env {OCMTS_ROOT: $tmp} {
            let result = (
                try { validate-actor-config "share-with" $tmp "nextcloud" "nextcloud"; "ok" }
                catch {|e| $"error: ($e.msg)"}
            )
            [
                (assert-truthy ($result | str starts-with "error:") "shape mismatch causes an error")
                (assert-string-contains $result "two_party" "error mentions two_party")
                (assert-string-contains $result "share-with__nextcloud__nextcloud" "error names the matrix entry")
            ]
        }
    }
}

def test-empty-override-errors [] {
    test-log "\n[test-empty-override-errors]"
    with-tmp-dir {|tmp|
        write-minimal-fixture $tmp
        ("{}" | save --force ($tmp | path join "config/actors/overrides/login__nextcloud.nuon"))
        with-env {OCMTS_ROOT: $tmp} {
            let result = (
                try { validate-actor-config "login" $tmp "nextcloud" ""; "ok" }
                catch {|e| $"error: ($e.msg)"}
            )
            [
                (assert-truthy ($result | str starts-with "error:") "empty override file causes an error")
                (assert-string-contains $result "has no real overrides" "error mentions has no real overrides")
            ]
        }
    }
}

def test-empty-string-override-errors [] {
    test-log "\n[test-empty-string-override-errors]"
    with-tmp-dir {|tmp|
        write-minimal-fixture $tmp
        ({actor: {account: ""}} | to nuon)
        | save --force ($tmp | path join "config/actors/overrides/login__nextcloud.nuon")
        with-env {OCMTS_ROOT: $tmp} {
            let result = (
                try { validate-actor-config "login" $tmp "nextcloud" ""; "ok" }
                catch {|e| $"error: ($e.msg)"}
            )
            [
                (assert-truthy ($result | str starts-with "error:")
                    "empty-string override file causes an error")
                (assert-string-contains $result "has no real overrides"
                    "empty-string override error mentions has no real overrides")
            ]
        }
    }
}

def test-one-party-rejects-spurious-receiver [] {
    test-log "\n[test-one-party-rejects-spurious-receiver]"
    with-tmp-dir {|tmp|
        write-minimal-fixture $tmp
        with-env {OCMTS_ROOT: $tmp} {
            let result = (
                try { validate-actor-config "login" $tmp "nextcloud" "ocmgo"; "ok" }
                catch {|e| $"error: ($e.msg)"}
            )
            [
                (assert-truthy ($result | str starts-with "error:")
                    "one-party tuple with spurious receiver causes an error")
                (assert-string-contains $result "one-party"
                    "spurious receiver error names one-party")
                (assert-string-contains $result "--receiver-platform"
                    "spurious receiver error names --receiver-platform")
            ]
        }
    }
}

def test-absent-matrix-entry-errors-clearly [] {
    test-log "\n[test-absent-matrix-entry-errors-clearly]"
    with-tmp-dir {|tmp|
        write-minimal-fixture $tmp
        with-env {OCMTS_ROOT: $tmp} {
            let result = (
                try { validate-actor-config "login" $tmp "ocmgo" ""; "ok" }
                catch {|e| $"error: ($e.msg)"}
            )
            [
                (assert-truthy ($result | str starts-with "error:")
                    "absent matrix entry causes an error")
                (assert-string-contains $result "not in config/matrix"
                    "absent matrix entry error names config/matrix")
            ]
        }
    }
}

def test-disabled-matrix-entry-errors-clearly [] {
    test-log "\n[test-disabled-matrix-entry-errors-clearly]"
    with-tmp-dir {|tmp|
        write-minimal-fixture $tmp
        with-env {OCMTS_ROOT: $tmp} {
            let result = (
                try {
                    validate-actor-config "contact-wayf" $tmp "nextcloud" "ocmgo"
                    "ok"
                } catch {|e| $"error: ($e.msg)"}
            )
            [
                (assert-truthy ($result | str starts-with "error:")
                    "disabled matrix entry causes an error")
                (assert-string-contains $result "disabled"
                    "disabled matrix entry error names disabled status")
                (assert-string-contains $result "contact-wayf__nextcloud__ocmgo"
                    "disabled matrix entry error names matrix_key")
            ]
        }
    }
}

def test-missing-sender-platform-errors-clearly [] {
    test-log "\n[test-missing-sender-platform-errors-clearly]"
    with-tmp-dir {|tmp|
        write-minimal-fixture $tmp
        with-env {OCMTS_ROOT: $tmp} {
            let result = (
                try { validate-actor-config "login" $tmp "" ""; "ok" }
                catch {|e| $"error: ($e.msg)"}
            )
            [
                (assert-truthy ($result | str starts-with "error:")
                    "missing sender platform causes an error")
                (assert-string-contains $result "--sender-platform is required"
                    "missing sender error names --sender-platform")
            ]
        }
    }
}

def test-validate-actor-config-rejects-path-traversal-flow-id [] {
    test-log "\n[test-validate-actor-config-rejects-path-traversal-flow-id]"
    with-tmp-dir {|tmp|
        write-minimal-fixture $tmp
        with-env {OCMTS_ROOT: $tmp} {
            let result = (
                try { validate-actor-config "../../../etc/passwd" $tmp "nextcloud" ""; "ok" }
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

def main [] {
    test-log "=== actors/validate Tests ==="
    let results = (
        (test-one-party-no-override-ok)
        | append (test-two-party-no-override-ok)
        | append (test-two-party-missing-receiver-errors-clearly)
        | append (test-one-party-rejects-spurious-receiver)
        | append (test-absent-matrix-entry-errors-clearly)
        | append (test-disabled-matrix-entry-errors-clearly)
        | append (test-missing-sender-platform-errors-clearly)
        | append (test-override-shape-mismatch)
        | append (test-empty-override-errors)
        | append (test-empty-string-override-errors)
        | append (test-validate-actor-config-rejects-path-traversal-flow-id)
    ) | flatten
    run-suite "actors/validate" $SUITE_PATH $results
}
