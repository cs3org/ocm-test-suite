# Actor loader tests.
# Run: nu scripts/tests/actors/load.nu
# Returns exit 0 on all pass, exit 1 with details on failure.
# Uses hermetic tmp fixtures so the real config tree is not required.

const SUITE_PATH = path self

use ../../lib/actors/load.nu [
    load-actor-for-scenario
    load-sender-for-scenario
    load-receiver-for-scenario
    list-override-files
    list-matrix-scenarios
]
use ../../lib/tests/assert.nu *
use ../../lib/tests/runner.nu [run-suite]
use ../../lib/tests/fixtures.nu [with-tmp-dir]

# Build a minimal but valid ocmts root fixture under tmp_root.
# Provides two scenarios: login (one-party) and share-with (two-party).
def write-minimal-fixture [tmp_root: string] {
    mkdir ($tmp_root | path join "config/matrix/flows")
    mkdir ($tmp_root | path join "config/actors/scenarios")
    mkdir ($tmp_root | path join "config/actors/platforms")

    ({browsers_default: ["chromium"]} | to nuon)
    | save --force ($tmp_root | path join "config/matrix/defaults.nuon")

    ({platforms: {
        nextcloud: {slug: "nc", version_lines: ["v32"]},
        ocmgo: {slug: "ocmgo", version_lines: ["v1"]}
    }} | to nuon)
    | save --force ($tmp_root | path join "config/matrix/platforms.nuon")

    ({baseline_by_flow: {
        login: {sender: "nextcloud", receiver: null},
        "share-with": {sender: "nextcloud", receiver: "nextcloud"}
    }, overrides: {}} | to nuon)
    | save --force ($tmp_root | path join "config/matrix/naming.nuon")

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

# load-actor-for-scenario with no override file resolves via matrix + defaults.
def test-actor-no-override [] {
    test-log "\n[test-actor-no-override]"
    with-tmp-dir {|tmp|
        write-minimal-fixture $tmp
        with-env {OCMTS_ROOT: $tmp} {
            let result = (load-actor-for-scenario "login" $tmp)
            [
                (assert-eq $result.platform "nextcloud"
                    "platform resolved from matrix")
                (assert-eq $result.account "michiel"
                    "account resolved from defaults")
                (assert-truthy (not ($result.username | is-empty))
                    "username is non-empty")
                (assert-truthy (not ($result.password | is-empty))
                    "password is non-empty")
            ]
        }
    }
}

# load-sender-for-scenario for a two-party scenario with no override resolves.
def test-sender-no-override [] {
    test-log "\n[test-sender-no-override]"
    with-tmp-dir {|tmp|
        write-minimal-fixture $tmp
        with-env {OCMTS_ROOT: $tmp} {
            let result = (load-sender-for-scenario "share-with" $tmp)
            [
                (assert-eq $result.platform "nextcloud"
                    "sender platform resolved from matrix")
                (assert-eq $result.account "michiel"
                    "sender account resolved from defaults")
            ]
        }
    }
}

# load-receiver-for-scenario for a one-party scenario returns null.
def test-receiver-one-party-null [] {
    test-log "\n[test-receiver-one-party-null]"
    with-tmp-dir {|tmp|
        write-minimal-fixture $tmp
        with-env {OCMTS_ROOT: $tmp} {
            let result = (load-receiver-for-scenario "login" $tmp)
            [
                (assert-null $result
                    "receiver is null for one-party matrix scenario")
            ]
        }
    }
}

# load-receiver-for-scenario for a two-party scenario with no override resolves.
def test-receiver-two-party-no-override [] {
    test-log "\n[test-receiver-two-party-no-override]"
    with-tmp-dir {|tmp|
        write-minimal-fixture $tmp
        with-env {OCMTS_ROOT: $tmp} {
            let result = (load-receiver-for-scenario "share-with" $tmp)
            [
                (assert-eq $result.platform "nextcloud"
                    "receiver platform resolved from matrix")
                (assert-eq $result.account "marie"
                    "receiver account resolved from defaults")
            ]
        }
    }
}

# Override file present with real overrides: override account wins over defaults.
def test-override-account-wins [] {
    test-log "\n[test-override-account-wins]"
    with-tmp-dir {|tmp|
        write-minimal-fixture $tmp
        ({actor: {account: "marie"}} | to nuon)
        | save --force ($tmp | path join "config/actors/scenarios/login.nuon")
        with-env {OCMTS_ROOT: $tmp} {
            let result = (load-actor-for-scenario "login" $tmp)
            [
                (assert-eq $result.account "marie"
                    "override account wins over defaults")
                (assert-eq $result.platform "nextcloud"
                    "platform still resolved from matrix when not overridden")
            ]
        }
    }
}

# Override file present but all role fields empty or missing -> hard error.
def test-empty-override-hard-error [] {
    test-log "\n[test-empty-override-hard-error]"
    with-tmp-dir {|tmp|
        write-minimal-fixture $tmp
        ("{}" | save --force ($tmp | path join "config/actors/scenarios/login.nuon"))
        with-env {OCMTS_ROOT: $tmp} {
            let result = (
                try { load-actor-for-scenario "login" $tmp; "no-error" }
                catch {|e| $"error: ($e.msg)"}
            )
            [
                (assert-truthy ($result | str starts-with "error:")
                    "empty override file causes a hard error")
                (assert-string-contains $result "has no real overrides"
                    "error message mentions 'has no real overrides'")
            ]
        }
    }
}

# list-matrix-scenarios returns the matrix-enabled set sorted.
def test-list-matrix-scenarios [] {
    test-log "\n[test-list-matrix-scenarios]"
    with-tmp-dir {|tmp|
        write-minimal-fixture $tmp
        let result = (list-matrix-scenarios $tmp)
        [
            (assert-truthy ($result | is-not-empty)
                "matrix scenarios list is non-empty")
            (assert-list-contains $result "login"
                "login is in matrix scenarios")
            (assert-list-contains $result "share-with"
                "share-with is in matrix scenarios")
            (assert-eq $result ($result | sort)
                "matrix scenarios are sorted")
        ]
    }
}

# list-override-files returns basenames of files present in scenarios/, sorted.
def test-list-override-files [] {
    test-log "\n[test-list-override-files]"
    with-tmp-dir {|tmp|
        mkdir ($tmp | path join "config/actors/scenarios")
        ({actor: {account: "michiel"}} | to nuon)
        | save --force ($tmp | path join "config/actors/scenarios/login.nuon")
        ({sender: {account: "michiel"}} | to nuon)
        | save --force ($tmp | path join "config/actors/scenarios/share-with.nuon")
        let result = (list-override-files $tmp)
        [
            (assert-eq ($result | length) 2
                "two override files found")
            (assert-list-contains $result "login"
                "login is in override files")
            (assert-list-contains $result "share-with"
                "share-with is in override files")
            (assert-eq $result ($result | sort)
                "override files are sorted")
        ]
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
        | append (test-empty-override-hard-error)
        | append (test-list-matrix-scenarios)
        | append (test-list-override-files)
    ) | flatten
    run-suite "actors/load" $SUITE_PATH $results
}
