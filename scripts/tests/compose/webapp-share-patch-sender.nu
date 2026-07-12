# sender-hub sender.yml patch direct unit coverage (topology-sender-hub.nu).
# Run: nu scripts/tests/compose/webapp-share-patch-sender.nu

const SUITE_PATH = path self

use ../../lib/compose/topology-sender-hub.nu [
    SENDER_HUB_JUPYTER_ENV_LINE
    SENDER_HUB_NO_PROXY_MARKER
    SENDER_HUB_OAUTH_ENV_LINE
    SENDER_HUB_OAUTH_VOLUME_LINE
    SENDER_HUB_VOLUMES_MARKER
    patch-sender-hub-sender-yml
]
use ../../lib/tests/assert.nu *
use ../../lib/tests/runner.nu [run-suite]

const PATCH_NO_PROXY_MARKER = $SENDER_HUB_NO_PROXY_MARKER
const PATCH_ACTORS_VOL_MARKER = $SENDER_HUB_VOLUMES_MARKER
const PATCH_JUPYTER_ENV_LINE = $SENDER_HUB_JUPYTER_ENV_LINE
const PATCH_OAUTH_ENV_LINE = $SENDER_HUB_OAUTH_ENV_LINE
const PATCH_OAUTH_VOL_LINE = $SENDER_HUB_OAUTH_VOLUME_LINE

def did-throw [cl: closure] {
    try { do $cl; false } catch { true }
}

def write-sender-fixture [lines: list<string>] {
    let dir = ($nu.temp-dir | path join $"patch-sender-fixture-(random uuid)")
    mkdir $dir
    ($lines | str join (char newline)) | save --force ($dir | path join "sender.yml")
    $dir
}

def test-patch-sender-happy-and-idempotent [] {
    test-log "\n[test-patch-sender-happy-and-idempotent]"
    let dir = (write-sender-fixture [
        "services:"
        "  sender:"
        "    environment:"
        $PATCH_NO_PROXY_MARKER
        "    volumes:"
        $PATCH_ACTORS_VOL_MARKER
    ])
    let sender_path = ($dir | path join "sender.yml")
    patch-sender-hub-sender-yml $dir
    let once = (open -r $sender_path)
    # A second call must be a no-op (fully patched), not an error or a re-inject.
    patch-sender-hub-sender-yml $dir
    let twice = (open -r $sender_path)
    let results = [
        (assert-string-contains $once $PATCH_JUPYTER_ENV_LINE
            "patch injects JUPYTER_HOST env line")
        (assert-string-contains $once $PATCH_OAUTH_ENV_LINE
            "patch injects OAuth env-file line")
        (assert-string-contains $once $PATCH_OAUTH_VOL_LINE
            "patch injects OAuth handoff volume line")
        (assert-eq $twice $once
            "second patch is idempotent (no double-inject, no error)")
    ]
    rm -rf $dir
    $results
}

def test-patch-sender-marker-miss-fails [] {
    test-log "\n[test-patch-sender-marker-miss-fails]"
    # sender.yml missing the NO_PROXY marker must fail fast, not silently no-op.
    let dir = (write-sender-fixture [
        "services:"
        "  sender:"
        "    environment:"
        "      - SOME_OTHER=1"
        "    volumes:"
        $PATCH_ACTORS_VOL_MARKER
    ])
    let threw = (did-throw {|| patch-sender-hub-sender-yml $dir })
    rm -rf $dir
    [
        (assert-truthy $threw
            "patch fails fast when the NO_PROXY marker is absent (no silent no-op)")
    ]
}

def test-patch-sender-volumes-marker-miss-fails [] {
    test-log "\n[test-patch-sender-volumes-marker-miss-fails]"
    # sender.yml missing the actors volume marker must fail fast, not silently no-op.
    let dir = (write-sender-fixture [
        "services:"
        "  sender:"
        "    environment:"
        $PATCH_NO_PROXY_MARKER
        "    volumes:"
        "      - SOME_OTHER=/tmp:ro"
    ])
    let threw = (did-throw {|| patch-sender-hub-sender-yml $dir })
    rm -rf $dir
    [
        (assert-truthy $threw
            "patch fails fast when the actors volume marker is absent (no silent no-op)")
    ]
}

def test-patch-sender-partial-fails [] {
    test-log "\n[test-patch-sender-partial-fails]"
    # Already carries JUPYTER_HOST but not the OAuth lines -> drifted/partial;
    # patch must refuse rather than corrupt the overlay.
    let dir = (write-sender-fixture [
        "services:"
        "  sender:"
        "    environment:"
        $PATCH_NO_PROXY_MARKER
        $PATCH_JUPYTER_ENV_LINE
        "    volumes:"
        $PATCH_ACTORS_VOL_MARKER
    ])
    let threw = (did-throw {|| patch-sender-hub-sender-yml $dir })
    rm -rf $dir
    [
        (assert-truthy $threw
            "patch refuses to re-patch a partially-patched (drifted) overlay")
    ]
}

def main [] {
    test-log "=== compose/webapp-share-patch-sender Tests ==="
    let results = (
        (test-patch-sender-happy-and-idempotent)
        | append (test-patch-sender-marker-miss-fails)
        | append (test-patch-sender-volumes-marker-miss-fails)
        | append (test-patch-sender-partial-fails)
    ) | flatten
    run-suite "compose/webapp-share-patch-sender" $SUITE_PATH $results
}
