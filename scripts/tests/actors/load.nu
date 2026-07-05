# Actor loader tests.
# Run: nu scripts/tests/actors/load.nu

const SUITE_PATH = path self

use ../../lib/actors/load.nu [
    load-actor-for-tuple
    load-sender-for-tuple
    load-receiver-for-tuple
    list-override-files
    list-matrix-keys
]
use ../../lib/domain/core/ocmts-root.nu [get-ocmts-root]
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

def test-actor-no-override [] {
    test-log "\n[test-actor-no-override]"
    with-tmp-dir {|tmp|
        write-minimal-fixture $tmp
        with-env {OCMTS_ROOT: $tmp} {
            let result = (load-actor-for-tuple "login" "nextcloud" $tmp)
            [
                (assert-eq $result.platform "nextcloud" "platform resolved from matrix")
                (assert-eq $result.account "michiel" "account resolved from defaults")
                (assert-truthy (not ($result.username | is-empty)) "username is non-empty")
                (assert-truthy (not ($result.password | is-empty)) "password is non-empty")
            ]
        }
    }
}

def test-sender-no-override [] {
    test-log "\n[test-sender-no-override]"
    with-tmp-dir {|tmp|
        write-minimal-fixture $tmp
        with-env {OCMTS_ROOT: $tmp} {
            let result = (load-sender-for-tuple "share-with" "nextcloud" "nextcloud" $tmp)
            [
                (assert-eq $result.platform "nextcloud" "sender platform resolved from matrix")
                (assert-eq $result.account "michiel" "sender account resolved from defaults")
            ]
        }
    }
}

def test-receiver-one-party-null [] {
    test-log "\n[test-receiver-one-party-null]"
    with-tmp-dir {|tmp|
        write-minimal-fixture $tmp
        with-env {OCMTS_ROOT: $tmp} {
            let result = (load-receiver-for-tuple "login" "nextcloud" "" $tmp)
            [(assert-null $result "receiver is null for one-party matrix entry")]
        }
    }
}

def test-receiver-two-party-no-override [] {
    test-log "\n[test-receiver-two-party-no-override]"
    with-tmp-dir {|tmp|
        write-minimal-fixture $tmp
        with-env {OCMTS_ROOT: $tmp} {
            let result = (load-receiver-for-tuple "share-with" "nextcloud" "nextcloud" $tmp)
            [
                (assert-eq $result.platform "nextcloud" "receiver platform resolved from matrix")
                (assert-eq $result.account "marie" "receiver account resolved from defaults")
            ]
        }
    }
}

def test-override-account-wins [] {
    test-log "\n[test-override-account-wins]"
    with-tmp-dir {|tmp|
        write-minimal-fixture $tmp
        ({actor: {account: "marie"}} | to nuon)
        | save --force ($tmp | path join "config/actors/overrides/login__nextcloud.nuon")
        with-env {OCMTS_ROOT: $tmp} {
            let result = (load-actor-for-tuple "login" "nextcloud" $tmp)
            [
                (assert-eq $result.account "marie" "override account wins over defaults")
                (assert-eq $result.platform "nextcloud" "platform still resolved from matrix")
            ]
        }
    }
}

def test-empty-override-hard-error [] {
    test-log "\n[test-empty-override-hard-error]"
    with-tmp-dir {|tmp|
        write-minimal-fixture $tmp
        ("{}" | save --force ($tmp | path join "config/actors/overrides/login__nextcloud.nuon"))
        with-env {OCMTS_ROOT: $tmp} {
            let result = (
                try { load-actor-for-tuple "login" "nextcloud" $tmp; "no-error" }
                catch {|e| $"error: ($e.msg)"}
            )
            [
                (assert-truthy ($result | str starts-with "error:") "empty override file causes a hard error")
                (assert-string-contains $result "has no real overrides" "error mentions has no real overrides")
            ]
        }
    }
}

def test-list-matrix-keys [] {
    test-log "\n[test-list-matrix-keys]"
    with-tmp-dir {|tmp|
        write-minimal-fixture $tmp
        let result = (list-matrix-keys $tmp)
        [
            (assert-truthy ($result | is-not-empty) "matrix keys list is non-empty")
            (assert-list-contains $result "login__nextcloud" "login__nextcloud is in matrix keys")
            (assert-list-contains $result "share-with__nextcloud__nextcloud" "share-with tuple is in matrix keys")
            (assert-eq $result ($result | sort) "matrix keys are sorted")
        ]
    }
}

def test-list-override-files [] {
    test-log "\n[test-list-override-files]"
    with-tmp-dir {|tmp|
        mkdir ($tmp | path join "config/actors/overrides")
        ({actor: {account: "michiel"}} | to nuon)
        | save --force ($tmp | path join "config/actors/overrides/login__nextcloud.nuon")
        ({sender: {account: "michiel"}} | to nuon)
        | save --force ($tmp | path join "config/actors/overrides/share-with__nextcloud__nextcloud.nuon")
        let result = (list-override-files $tmp)
        [
            (assert-eq ($result | length) 2 "two override files found")
            (assert-list-contains $result "login__nextcloud" "login override is listed")
            (assert-list-contains $result "share-with__nextcloud__nextcloud" "share-with override is listed")
            (assert-eq $result ($result | sort) "override files are sorted")
        ]
    }
}

def test-empty-string-override-hard-error [] {
    test-log "\n[test-empty-string-override-hard-error]"
    with-tmp-dir {|tmp|
        write-minimal-fixture $tmp
        ({actor: {account: ""}} | to nuon)
        | save --force ($tmp | path join "config/actors/overrides/login__nextcloud.nuon")
        with-env {OCMTS_ROOT: $tmp} {
            let result = (
                try { load-actor-for-tuple "login" "nextcloud" $tmp; "no-error" }
                catch {|e| $"error: ($e.msg)"}
            )
            [
                (assert-truthy ($result | str starts-with "error:")
                    "override with only empty string values causes a hard error")
                (assert-string-contains $result "has no real overrides"
                    "empty-string override error mentions has no real overrides")
            ]
        }
    }
}

def test-override-platform-mismatch-errors [] {
    test-log "\n[test-override-platform-mismatch-errors]"
    with-tmp-dir {|tmp|
        write-minimal-fixture $tmp
        ({sender: {platform: "ocmgo", account: "michiel"}} | to nuon)
        | save --force ($tmp | path join "config/actors/overrides/share-with__nextcloud__nextcloud.nuon")
        with-env {OCMTS_ROOT: $tmp} {
            let result = (
                try {
                    load-sender-for-tuple "share-with" "nextcloud" "nextcloud" $tmp "nextcloud"
                    "ok"
                } catch {|e| $"error: ($e.msg)"}
            )
            [
                (assert-truthy ($result | str starts-with "error:")
                    "override platform mismatch causes an error")
                (assert-string-contains $result "mismatches expected"
                    "override platform mismatch error names mismatches expected")
            ]
        }
    }
}

def test-absent-matrix-entry-hard-error [] {
    test-log "\n[test-absent-matrix-entry-hard-error]"
    with-tmp-dir {|tmp|
        write-minimal-fixture $tmp
        with-env {OCMTS_ROOT: $tmp} {
            let result = (
                try { load-actor-for-tuple "login" "ocmgo" $tmp; "no-error" }
                catch {|e| $"error: ($e.msg)"}
            )
            [
                (assert-truthy ($result | str starts-with "error:")
                    "absent matrix entry causes a hard error")
                (assert-string-contains $result "not in config/matrix"
                    "absent matrix entry error names config/matrix")
            ]
        }
    }
}

def test-contact-token-cernbox-sender-real-repo [] {
    test-log "\n[test-contact-token-cernbox-sender-real-repo]"
    let root = get-ocmts-root
    let result = (load-sender-for-tuple "contact-token" "cernbox" "cernbox" $root)
    [
        (assert-eq $result.platform "cernbox"
            "contact-token cernbox sender platform resolves from matrix")
        (assert-eq $result.account "einstein"
            "contact-token cernbox sender account resolves to einstein")
    ]
}

def test-contact-token-cernbox-receiver-real-repo [] {
    test-log "\n[test-contact-token-cernbox-receiver-real-repo]"
    let root = get-ocmts-root
    let result = (load-receiver-for-tuple "contact-token" "cernbox" "cernbox" $root)
    [
        (assert-eq $result.platform "cernbox"
            "contact-token cernbox receiver platform resolves from matrix")
        (assert-eq $result.account "marie"
            "contact-token cernbox receiver account resolves to marie")
    ]
}

def test-list-matrix-keys-includes-contact-token-cernbox [] {
    test-log "\n[test-list-matrix-keys-includes-contact-token-cernbox]"
    let root = get-ocmts-root
    let result = (list-matrix-keys $root)
    [
        (assert-list-contains $result "contact-token__cernbox__cernbox"
            "contact-token__cernbox__cernbox is in real matrix keys")
    ]
}

def test-disabled-matrix-entry-hard-error [] {
    test-log "\n[test-disabled-matrix-entry-hard-error]"
    with-tmp-dir {|tmp|
        write-minimal-fixture $tmp
        with-env {OCMTS_ROOT: $tmp} {
            let result = (
                try {
                    load-sender-for-tuple "contact-wayf" "nextcloud" "ocmgo" $tmp
                    "no-error"
                } catch {|e| $"error: ($e.msg)"}
            )
            [
                (assert-truthy ($result | str starts-with "error:")
                    "disabled matrix entry causes a hard error")
                (assert-string-contains $result "disabled"
                    "disabled matrix entry error names disabled status")
                (assert-string-contains $result "Placeholder cells cannot be run"
                    "disabled matrix entry error uses unified disabled wording")
            ]
        }
    }
}

def main [] {
    test-log "=== actors/load Tests ==="
    let results = (
        (test-actor-no-override)
        | append (test-sender-no-override)
        | append (test-receiver-one-party-null)
        | append (test-receiver-two-party-no-override)
        | append (test-override-account-wins)
        | append (test-override-platform-mismatch-errors)
        | append (test-empty-override-hard-error)
        | append (test-empty-string-override-hard-error)
        | append (test-absent-matrix-entry-hard-error)
        | append (test-disabled-matrix-entry-hard-error)
        | append (test-list-matrix-keys)
        | append (test-list-override-files)
        | append (test-contact-token-cernbox-sender-real-repo)
        | append (test-contact-token-cernbox-receiver-real-repo)
        | append (test-list-matrix-keys-includes-contact-token-cernbox)
    ) | flatten
    run-suite "actors/load" $SUITE_PATH $results
}
