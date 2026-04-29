# Actor validator tests.
# Run: nu scripts/tests/actors/validate.nu
# Returns exit 0 on all pass, exit 1 with details on failure.
# Uses hermetic tmp fixtures so the real config tree is not required.

const SUITE_PATH = path self

use ../../lib/actors/validate.nu [validate-actor-config]
use ../../lib/tests/assert.nu *
use ../../lib/tests/runner.nu [run-suite]
use ../../lib/tests/fixtures.nu [with-tmp-dir]

# Same minimal fixture as the load tests.
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

# validate-actor-config for a one-party scenario with no override file passes.
def test-one-party-no-override-ok [] {
    test-log "\n[test-one-party-no-override-ok]"
    with-tmp-dir {|tmp|
        write-minimal-fixture $tmp
        with-env {OCMTS_ROOT: $tmp} {
            let result = (
                try { validate-actor-config "login" $tmp --flow-id "login"; "ok" }
                catch {|e| $"error: ($e.msg)"}
            )
            [
                (assert-eq $result "ok"
                    "one-party scenario with no override file validates ok")
            ]
        }
    }
}

# validate-actor-config for a two-party scenario with no override file passes.
def test-two-party-no-override-ok [] {
    test-log "\n[test-two-party-no-override-ok]"
    with-tmp-dir {|tmp|
        write-minimal-fixture $tmp
        with-env {OCMTS_ROOT: $tmp} {
            let result = (
                try { validate-actor-config "share-with" $tmp --flow-id "share-with"; "ok" }
                catch {|e| $"error: ($e.msg)"}
            )
            [
                (assert-eq $result "ok"
                    "two-party scenario with no override file validates ok")
            ]
        }
    }
}

# Override file has actor field but matrix says two-party -> topology mismatch.
def test-override-shape-mismatch [] {
    test-log "\n[test-override-shape-mismatch]"
    with-tmp-dir {|tmp|
        write-minimal-fixture $tmp
        ({actor: {account: "michiel"}} | to nuon)
        | save --force ($tmp | path join "config/actors/scenarios/share-with.nuon")
        with-env {OCMTS_ROOT: $tmp} {
            let result = (
                try { validate-actor-config "share-with" $tmp --flow-id "share-with"; "ok" }
                catch {|e| $"error: ($e.msg)"}
            )
            [
                (assert-truthy ($result | str starts-with "error:")
                    "shape mismatch causes an error")
                (assert-string-contains $result "two_party"
                    "error mentions two_party")
                (assert-string-contains $result "share-with"
                    "error names the scenario")
            ]
        }
    }
}

# Override file is empty -> error from the underlying loader's empty-override check.
def test-empty-override-errors [] {
    test-log "\n[test-empty-override-errors]"
    with-tmp-dir {|tmp|
        write-minimal-fixture $tmp
        ("{}" | save --force ($tmp | path join "config/actors/scenarios/login.nuon"))
        with-env {OCMTS_ROOT: $tmp} {
            let result = (
                try { validate-actor-config "login" $tmp --flow-id "login"; "ok" }
                catch {|e| $"error: ($e.msg)"}
            )
            [
                (assert-truthy ($result | str starts-with "error:")
                    "empty override file causes an error during validation")
                (assert-string-contains $result "has no real overrides"
                    "error message mentions 'has no real overrides'")
            ]
        }
    }
}

def main [] {
    test-log "=== actors/validate Tests ==="
    let results = (
        (test-one-party-no-override-ok)
        | append (test-two-party-no-override-ok)
        | append (test-override-shape-mismatch)
        | append (test-empty-override-errors)
    ) | flatten
    run-suite "actors/validate" $SUITE_PATH $results
}
