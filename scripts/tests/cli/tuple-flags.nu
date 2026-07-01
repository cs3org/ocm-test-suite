# Tuple CLI flag regression tests.
# Run: nu scripts/tests/cli/tuple-flags.nu
# Guards the tuple-identity cutover: legacy --scenario must stay removed.

const SUITE_PATH = path self

use ../../lib/tests/assert.nu *
use ../../lib/tests/runner.nu [run-suite]

def repo-root [] {
    $SUITE_PATH | path dirname | path dirname | path dirname | path dirname
}

def ocmts-script [] {
    (repo-root) | path join "scripts/ocmts.nu"
}

def assert-scenario-flag-rejected [cmd: list<string>, label: string] {
    let out = (^nu (ocmts-script) ...$cmd | complete)
    [
        (assert-eq $out.exit_code 1
            $"($label): --scenario exits 1")
        (assert-truthy (
            ($out.stderr | str contains "unknown_flag")
            or ($out.stderr | str contains "doesn't have flag `scenario`")
            or ($out.stderr | str contains "doesn't have flag 'scenario'")
        ) $"($label): stderr reports unknown --scenario flag")
    ]
}

def test-matrix-cell-rejects-scenario-flag [] {
    test-log "\n[test-matrix-cell-rejects-scenario-flag]"
    assert-scenario-flag-rejected [
        matrix cell
        --flow login
        --sender-platform nextcloud
        --sender-version v32
        --scenario login
    ] "matrix cell"
}

def test-actors-show-rejects-scenario-flag [] {
    test-log "\n[test-actors-show-rejects-scenario-flag]"
    assert-scenario-flag-rejected [
        actors show
        --flow login
        --sender-platform nextcloud
        --scenario login
    ] "actors show"
}

def test-images-resolve-rejects-scenario-flag [] {
    test-log "\n[test-images-resolve-rejects-scenario-flag]"
    assert-scenario-flag-rejected [
        images resolve
        --flow login
        --sender-platform nextcloud
        --sender-version v32
        --scenario login
    ] "images resolve"
}

def test-actors-validate-rejects-scenario-flag [] {
    test-log "\n[test-actors-validate-rejects-scenario-flag]"
    assert-scenario-flag-rejected [
        actors validate
        --flow login
        --sender-platform nextcloud
        --scenario login
    ] "actors validate"
}

def test-services-up-run-rejects-scenario-flag [] {
    test-log "\n[test-services-up-run-rejects-scenario-flag]"
    assert-scenario-flag-rejected [
        services up run
        --flow login
        --sender-platform nextcloud
        --sender-version v32
        --scenario login
    ] "services up run"
}

def test-services-up-rejects-scenario-flag [] {
    test-log "\n[test-services-up-rejects-scenario-flag]"
    assert-scenario-flag-rejected [
        services up
        --flow login
        --sender-platform nextcloud
        --sender-version v32
        --scenario login
    ] "services up"
}

def test-services-up-open-rejects-scenario-flag [] {
    test-log "\n[test-services-up-open-rejects-scenario-flag]"
    assert-scenario-flag-rejected [
        services up open
        --flow login
        --sender-platform nextcloud
        --sender-version v32
        --scenario login
    ] "services up open"
}

def test-services-list-cell-images-rejects-scenario-flag [] {
    test-log "\n[test-services-list-cell-images-rejects-scenario-flag]"
    assert-scenario-flag-rejected [
        services list-cell-images
        --flow login
        --sender-platform nextcloud
        --sender-version v32
        --scenario login
    ] "services list-cell-images"
}

def test-services-down-rejects-scenario-flag [] {
    test-log "\n[test-services-down-rejects-scenario-flag]"
    assert-scenario-flag-rejected [
        services down
        --flow login
        --sender-platform nextcloud
        --sender-version v32
        --scenario login
    ] "services down"
}

def test-test-cypress-run-rejects-scenario-flag [] {
    test-log "\n[test-test-cypress-run-rejects-scenario-flag]"
    assert-scenario-flag-rejected [
        test cypress run
        --flow login
        --sender-platform nextcloud
        --sender-version v32
        --scenario login
    ] "test cypress run"
}

def test-artifacts-list-rejects-scenario-flag [] {
    test-log "\n[test-artifacts-list-rejects-scenario-flag]"
    assert-scenario-flag-rejected [
        artifacts list
        --flow login
        --sender-platform nextcloud
        --sender-version v32
        --scenario login
    ] "artifacts list"
}

def test-artifacts-collect-rejects-scenario-flag [] {
    test-log "\n[test-artifacts-collect-rejects-scenario-flag]"
    assert-scenario-flag-rejected [
        artifacts collect
        --flow login
        --sender-platform nextcloud
        --sender-version v32
        --scenario login
    ] "artifacts collect"
}

def test-artifacts-publish-rejects-scenario-flag [] {
    test-log "\n[test-artifacts-publish-rejects-scenario-flag]"
    assert-scenario-flag-rejected [
        artifacts publish
        --flow login
        --sender-platform nextcloud
        --sender-version v32
        --scenario login
    ] "artifacts publish"
}

def test-artifacts-prune-rejects-scenario-flag [] {
    test-log "\n[test-artifacts-prune-rejects-scenario-flag]"
    assert-scenario-flag-rejected [
        artifacts prune
        --flow login
        --sender-platform nextcloud
        --sender-version v32
        --scenario login
    ] "artifacts prune"
}

def test-artifacts-show-rejects-scenario-flag [] {
    test-log "\n[test-artifacts-show-rejects-scenario-flag]"
    assert-scenario-flag-rejected [
        artifacts show
        --flow login
        --sender-platform nextcloud
        --sender-version v32
        --scenario login
    ] "artifacts show"
}

def test-ci-emit-blocked-rejects-scenario-flag [] {
    test-log "\n[test-ci-emit-blocked-rejects-scenario-flag]"
    assert-scenario-flag-rejected [
        ci emit-blocked
        --execution-id 20260101t000000-aaaaaaaa
        --flow login
        --sender-platform nextcloud
        --sender-version v32
        --failure-reason blocked
        --scenario login
    ] "ci emit-blocked"
}

def test-help-does-not-mention-scenario-flag [] {
    test-log "\n[test-help-does-not-mention-scenario-flag]"
    let out = (^nu (ocmts-script) matrix cell --help | complete)
    [
        (assert-eq $out.exit_code 0
            "matrix cell --help exits 0")
        (assert-truthy (not ($out.stdout | str contains "--scenario"))
            "matrix cell --help does not list --scenario")
    ]
}

def test-matrix-cell-one-party-happy [] {
    test-log "\n[test-matrix-cell-one-party-happy]"
    let out = (^nu (ocmts-script) matrix cell
        --flow login
        --sender-platform nextcloud
        --sender-version v32
        --json
        | complete)
    let data = (try { $out.stdout | from json } catch { {} })
    [
        (assert-eq $out.exit_code 0
            "matrix cell one-party exits 0")
        (assert-eq $data.matrix_key "login__nextcloud"
            "matrix cell one-party resolves matrix_key")
        (assert-eq $data.cell_id "login__nextcloud-v32"
            "matrix cell one-party resolves cell_id")
        (assert-truthy (not ($data.images.platform? | default "" | is-empty))
            "matrix cell one-party resolves sender platform image")
    ]
}

def test-matrix-cell-two-party-happy [] {
    test-log "\n[test-matrix-cell-two-party-happy]"
    let out = (^nu (ocmts-script) matrix cell
        --flow share-with
        --sender-platform nextcloud
        --sender-version v32
        --receiver-platform ocmgo
        --receiver-version v1
        --json
        | complete)
    let data = (try { $out.stdout | from json } catch { {} })
    [
        (assert-eq $out.exit_code 0
            "matrix cell two-party exits 0")
        (assert-eq $data.matrix_key "share-with__nextcloud__ocmgo"
            "matrix cell two-party resolves matrix_key")
        (assert-eq $data.cell_id "share-with__nextcloud-v32__ocmgo-v1"
            "matrix cell two-party resolves cell_id")
        (assert-truthy (not ($data.receiver_image? | default "" | is-empty))
            "matrix cell two-party resolves receiver image")
    ]
}

def test-images-resolve-one-party-happy [] {
    test-log "\n[test-images-resolve-one-party-happy]"
    let out = (^nu (ocmts-script) images resolve
        --flow login
        --sender-platform nextcloud
        --sender-version v32
        --json
        | complete)
    let data = (try { $out.stdout | from json } catch { {} })
    [
        (assert-eq $out.exit_code 0
            "images resolve one-party exits 0")
        (assert-truthy (not ($data.platform? | default "" | is-empty))
            "images resolve one-party resolves sender platform image")
        (assert-truthy (not ($data.cypress_ci? | default "" | is-empty))
            "images resolve one-party resolves cypress_ci image")
    ]
}

def test-images-resolve-two-party-happy [] {
    test-log "\n[test-images-resolve-two-party-happy]"
    let out = (^nu (ocmts-script) images resolve
        --flow share-with
        --sender-platform nextcloud
        --sender-version v32
        --receiver-platform ocmgo
        --receiver-version v1
        --json
        | complete)
    let data = (try { $out.stdout | from json } catch { {} })
    [
        (assert-eq $out.exit_code 0
            "images resolve two-party exits 0")
        (assert-truthy (not ($data.receiver_platform? | default "" | is-empty))
            "images resolve two-party resolves receiver image")
        (assert-truthy (not ($data.mitmproxy? | default "" | is-empty))
            "images resolve two-party resolves mitmproxy image")
    ]
}

def main [] {
    test-log "=== cli/tuple-flags tests ==="
    let results = (
        (test-matrix-cell-rejects-scenario-flag)
        | append (test-actors-show-rejects-scenario-flag)
        | append (test-actors-validate-rejects-scenario-flag)
        | append (test-images-resolve-rejects-scenario-flag)
        | append (test-services-up-rejects-scenario-flag)
        | append (test-services-up-open-rejects-scenario-flag)
        | append (test-services-list-cell-images-rejects-scenario-flag)
        | append (test-services-up-run-rejects-scenario-flag)
        | append (test-services-down-rejects-scenario-flag)
        | append (test-test-cypress-run-rejects-scenario-flag)
        | append (test-artifacts-list-rejects-scenario-flag)
        | append (test-artifacts-collect-rejects-scenario-flag)
        | append (test-artifacts-publish-rejects-scenario-flag)
        | append (test-artifacts-prune-rejects-scenario-flag)
        | append (test-artifacts-show-rejects-scenario-flag)
        | append (test-ci-emit-blocked-rejects-scenario-flag)
        | append (test-help-does-not-mention-scenario-flag)
        | append (test-matrix-cell-one-party-happy)
        | append (test-matrix-cell-two-party-happy)
        | append (test-images-resolve-one-party-happy)
        | append (test-images-resolve-two-party-happy)
    ) | flatten
    run-suite "cli/tuple-flags" $SUITE_PATH $results
}
