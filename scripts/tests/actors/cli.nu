# Actor CLI smoke tests.
# Run: nu scripts/tests/actors/cli.nu
# Exercises the `actors list` and `actors list overrides` verbs against the
# real repo root. get-ocmts-root resolves via git when run from within the
# repo, so this test must be run from inside the ots-rebooted repo tree.

const SUITE_PATH = path self

use ../../lib/tests/assert.nu *
use ../../lib/tests/runner.nu [run-suite]
use ../../lib/tests/fixtures.nu [with-tmp-dir]

# Derive repo root from this file's own location.
def repo-root [] {
    $SUITE_PATH | path dirname | path dirname | path dirname | path dirname
}

def ocmts-script [] {
    (repo-root) | path join "scripts/ocmts.nu"
}

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
        "contact-wayf": {
            sender: {by_platform: {nextcloud: "michiel"}},
            receiver: {by_platform: {ocmgo: "marie"}}
        }
    }} | to nuon)
    | save --force ($tmp_root | path join "config/actors/defaults.nuon")

    ({accounts: {
        michiel: {username: "michiel_user", password: "michiel_pass"},
        marie: {username: "marie_user", password: "marie_pass"}
    }} | to nuon)
    | save --force ($tmp_root | path join "config/actors/platforms/nextcloud.nuon")
}

# `actors list` exits 0 and prints at least one matrix-enabled tuple.
def test-actors-list [] {
    test-log "\n[test-actors-list]"
    let out = (^nu (ocmts-script) actors list | complete)
    [
        (assert-eq $out.exit_code 0
            "actors list exits 0")
        (assert-string-contains $out.stdout "login__nextcloud"
            "actors list output contains login__nextcloud matrix key")
        (assert-string-contains $out.stdout "contact-token__cernbox__cernbox"
            "actors list output contains contact-token__cernbox__cernbox matrix key")
    ]
}

# `actors list overrides` exits 0 (may print nothing if no override files).
def test-actors-list-overrides [] {
    test-log "\n[test-actors-list-overrides]"
    let out = (^nu (ocmts-script) actors list overrides | complete)
    [
        (assert-eq $out.exit_code 0
            "actors list overrides exits 0")
    ]
}

def test-actors-show-one-party [] {
    test-log "\n[test-actors-show-one-party]"
    let out = (^nu (ocmts-script) actors show
        --flow login
        --sender-platform nextcloud
        | complete)
    [
        (assert-eq $out.exit_code 0
            "actors show one-party exits 0")
        (assert-string-contains $out.stdout "matrix_key: login__nextcloud"
            "actors show one-party prints resolved matrix_key")
        (assert-string-contains $out.stdout "account:    michiel"
            "actors show one-party prints resolved actor account")
    ]
}

def test-actors-show-two-party-requires-receiver [] {
    test-log "\n[test-actors-show-two-party-requires-receiver]"
    let out = (^nu (ocmts-script) actors show
        --flow share-with
        --sender-platform nextcloud
        | complete)
    [
        (assert-eq $out.exit_code 1
            "actors show two-party without receiver exits 1")
        (assert-string-contains $out.stderr "requires --receiver-platform"
            "actors show missing receiver error names --receiver-platform")
        (assert-string-contains $out.stderr "share-with"
            "actors show missing receiver error names flow")
    ]
}

def test-actors-show-two-party [] {
    test-log "\n[test-actors-show-two-party]"
    let out = (^nu (ocmts-script) actors show
        --flow share-with
        --sender-platform nextcloud
        --receiver-platform ocmgo
        | complete)
    [
        (assert-eq $out.exit_code 0
            "actors show two-party exits 0")
        (assert-string-contains $out.stdout "matrix_key: share-with__nextcloud__ocmgo"
            "actors show two-party prints resolved matrix_key")
        (assert-string-contains $out.stdout "receiver:"
            "actors show two-party prints receiver block")
    ]
}

def test-actors-show-contact-token-cernbox-cernbox [] {
    test-log "\n[test-actors-show-contact-token-cernbox-cernbox]"
    let out = (^nu (ocmts-script) actors show
        --flow contact-token
        --sender-platform cernbox
        --receiver-platform cernbox
        | complete)
    let sender_block = ($out.stdout | split row "sender:" | last | split row "receiver:" | first)
    let receiver_block = ($out.stdout | split row "receiver:" | last)
    [
        (assert-eq $out.exit_code 0
            "actors show contact-token cernbox/cernbox exits 0")
        (assert-string-contains $out.stdout "matrix_key: contact-token__cernbox__cernbox"
            "actors show contact-token cernbox/cernbox prints resolved matrix_key")
        (assert-string-contains $sender_block "account:    einstein"
            "actors show contact-token cernbox/cernbox sender block prints einstein")
        (assert-string-contains $receiver_block "account:    marie"
            "actors show contact-token cernbox/cernbox receiver block prints marie")
    ]
}

def test-actors-validate-contact-token-cernbox-cernbox [] {
    test-log "\n[test-actors-validate-contact-token-cernbox-cernbox]"
    let out = (^nu (ocmts-script) actors validate
        --flow contact-token
        --sender-platform cernbox
        --receiver-platform cernbox
        | complete)
    [
        (assert-eq $out.exit_code 0
            "actors validate contact-token cernbox/cernbox exits 0")
        (assert-string-contains $out.stdout "actor config for 'contact-token__cernbox__cernbox': ok"
            "actors validate contact-token cernbox/cernbox prints ok line")
    ]
}

def test-actors-validate-one-party [] {
    test-log "\n[test-actors-validate-one-party]"
    let out = (^nu (ocmts-script) actors validate
        --flow login
        --sender-platform nextcloud
        | complete)
    [
        (assert-eq $out.exit_code 0
            "actors validate one-party exits 0")
        (assert-string-contains $out.stdout "actor config for 'login__nextcloud': ok"
            "actors validate one-party prints ok line")
    ]
}

def test-actors-validate-two-party-requires-receiver [] {
    test-log "\n[test-actors-validate-two-party-requires-receiver]"
    let out = (^nu (ocmts-script) actors validate
        --flow share-with
        --sender-platform nextcloud
        | complete)
    [
        (assert-eq $out.exit_code 1
            "actors validate two-party without receiver exits 1")
        (assert-string-contains $out.stderr "requires --receiver-platform"
            "actors validate missing receiver error names --receiver-platform")
        (assert-string-contains $out.stderr "share-with"
            "actors validate missing receiver error names flow")
    ]
}

def test-actors-show-requires-sender-platform [] {
    test-log "\n[test-actors-show-requires-sender-platform]"
    let out = (^nu (ocmts-script) actors show --flow login | complete)
    [
        (assert-eq $out.exit_code 1
            "actors show without sender-platform exits 1")
        (assert-string-contains $out.stderr "--sender-platform is required"
            "actors show missing sender error names --sender-platform")
    ]
}

def actors-mod-script [] {
    (repo-root) | path join "scripts/domains/actors/mod.nu"
}

def test-actors-show-disabled-tuple-errors [] {
    test-log "\n[test-actors-show-disabled-tuple-errors]"
    with-tmp-dir {|tmp|
        write-minimal-fixture $tmp
        with-env {OCMTS_ROOT: $tmp} {
            let out = (^nu (actors-mod-script) show
                --flow contact-wayf
                --sender-platform nextcloud
                --receiver-platform ocmgo
                | complete)
            [
                (assert-eq $out.exit_code 1
                    "actors show disabled tuple exits 1")
                (assert-string-contains $out.stderr "disabled"
                    "actors show disabled tuple error names disabled status")
                (assert-string-contains $out.stderr "Placeholder cells cannot be run"
                    "actors show disabled tuple error uses unified disabled wording")
                (assert-string-contains $out.stderr "contact-wayf__nextcloud__ocmgo"
                    "actors show disabled tuple error names matrix_key")
                (assert-truthy (not ($out.stdout | str contains "password"))
                    "actors show disabled tuple does not print credentials")
            ]
        }
    }
}

def test-actors-show-absent-tuple-errors [] {
    test-log "\n[test-actors-show-absent-tuple-errors]"
    with-tmp-dir {|tmp|
        write-minimal-fixture $tmp
        with-env {OCMTS_ROOT: $tmp} {
            let out = (^nu (actors-mod-script) show
                --flow login
                --sender-platform ocmgo
                | complete)
            [
                (assert-eq $out.exit_code 1
                    "actors show absent tuple exits 1")
                (assert-string-contains $out.stderr "not in config/matrix"
                    "actors show absent tuple error names config/matrix")
                (assert-truthy (not ($out.stdout | str contains "password"))
                    "actors show absent tuple does not print credentials")
            ]
        }
    }
}

def test-actors-validate-disabled-tuple-errors [] {
    test-log "\n[test-actors-validate-disabled-tuple-errors]"
    with-tmp-dir {|tmp|
        write-minimal-fixture $tmp
        with-env {OCMTS_ROOT: $tmp} {
            let out = (^nu (actors-mod-script) validate
                --flow contact-wayf
                --sender-platform nextcloud
                --receiver-platform ocmgo
                | complete)
            [
                (assert-eq $out.exit_code 1
                    "actors validate disabled tuple exits 1")
                (assert-string-contains $out.stderr "disabled"
                    "actors validate disabled tuple error names disabled status")
                (assert-string-contains $out.stderr "Placeholder cells cannot be run"
                    "actors validate disabled tuple error uses unified disabled wording")
                (assert-string-contains $out.stderr "contact-wayf__nextcloud__ocmgo"
                    "actors validate disabled tuple error names matrix_key")
                (assert-truthy (not ($out.stdout | str contains "ok"))
                    "actors validate disabled tuple does not print ok line")
            ]
        }
    }
}

def test-actors-validate-absent-tuple-errors [] {
    test-log "\n[test-actors-validate-absent-tuple-errors]"
    with-tmp-dir {|tmp|
        write-minimal-fixture $tmp
        with-env {OCMTS_ROOT: $tmp} {
            let out = (^nu (actors-mod-script) validate
                --flow login
                --sender-platform ocmgo
                | complete)
            [
                (assert-eq $out.exit_code 1
                    "actors validate absent tuple exits 1")
                (assert-string-contains $out.stderr "not in config/matrix"
                    "actors validate absent tuple error names config/matrix")
                (assert-truthy (not ($out.stdout | str contains "ok"))
                    "actors validate absent tuple does not print ok line")
            ]
        }
    }
}

def test-actors-validate-all [] {
    test-log "\n[test-actors-validate-all]"
    let out = (^nu (ocmts-script) actors validate-all | complete)
    [
        (assert-eq $out.exit_code 0
            "actors validate-all exits 0")
        (assert-string-contains $out.stdout "login__nextcloud: ok"
            "actors validate-all includes login tuple")
        (assert-string-contains $out.stdout "share-with__nextcloud__ocmgo: ok"
            "actors validate-all includes migrated share-with tuple")
        (assert-string-contains $out.stdout "contact-token__cernbox__cernbox: ok"
            "actors validate-all includes contact-token cernbox/cernbox tuple")
    ]
}

def test-actors-validate-requires-sender-platform [] {
    test-log "\n[test-actors-validate-requires-sender-platform]"
    let out = (^nu (ocmts-script) actors validate --flow login | complete)
    [
        (assert-eq $out.exit_code 1
            "actors validate without sender-platform exits 1")
        (assert-string-contains $out.stderr "--sender-platform is required"
            "actors validate missing sender error names --sender-platform")
    ]
}

def test-actors-validate-rejects-invalid-flow-id [] {
    test-log "\n[test-actors-validate-rejects-invalid-flow-id]"
    let out = (^nu (actors-mod-script) validate
        --flow "login/evil"
        --sender-platform nextcloud
        | complete)
    [
        (assert-eq $out.exit_code 1
            "actors validate rejects slash in flow_id before topology lookup")
        (assert-string-contains $out.stderr "flow_id contains slash"
            "actors validate invalid flow_id error names flow_id segment rule")
        (assert-truthy (not ($out.stderr | str contains "Flow file not found"))
            "actors validate invalid flow_id does not reach flow file lookup")
    ]
}

def test-actors-show-rejects-invalid-flow-id [] {
    test-log "\n[test-actors-show-rejects-invalid-flow-id]"
    let out = (^nu (actors-mod-script) show
        --flow "login/evil"
        --sender-platform nextcloud
        | complete)
    [
        (assert-eq $out.exit_code 1
            "actors show rejects slash in flow_id before topology lookup")
        (assert-string-contains $out.stderr "flow_id contains slash"
            "actors show invalid flow_id error names flow_id segment rule")
        (assert-truthy (not ($out.stderr | str contains "Flow file not found"))
            "actors show invalid flow_id does not reach flow file lookup")
    ]
}

def main [] {
    test-log "=== actors/cli Tests ==="
    let results = (
        (test-actors-list)
        | append (test-actors-list-overrides)
        | append (test-actors-show-one-party)
        | append (test-actors-show-two-party-requires-receiver)
        | append (test-actors-show-two-party)
        | append (test-actors-show-contact-token-cernbox-cernbox)
        | append (test-actors-show-requires-sender-platform)
        | append (test-actors-show-disabled-tuple-errors)
        | append (test-actors-show-absent-tuple-errors)
        | append (test-actors-validate-disabled-tuple-errors)
        | append (test-actors-validate-absent-tuple-errors)
        | append (test-actors-validate-one-party)
        | append (test-actors-validate-contact-token-cernbox-cernbox)
        | append (test-actors-validate-requires-sender-platform)
        | append (test-actors-validate-two-party-requires-receiver)
        | append (test-actors-validate-rejects-invalid-flow-id)
        | append (test-actors-show-rejects-invalid-flow-id)
        | append (test-actors-validate-all)
    ) | flatten
    run-suite "actors/cli" $SUITE_PATH $results
}
