# emit-cell-images unit tests.
# Run: nu scripts/tests/images/emit-cell-images.nu
# Returns exit 0 on all pass, exit 1 with details on failure.

const SUITE_PATH = path self

use ../../lib/images/cell-images.nu [emit-cell-images]
use ../../lib/tests/assert.nu *
use ../../lib/tests/runner.nu [run-suite]

def make-tmp [] {
    let t = ($nu.temp-dir | path join $"images-emit-test-(random uuid)")
    mkdir $t
    $t
}

# Two-party shape: 7 entries, correct service/role/tag, no cypress entries.
def test-two-party-services-shape [] {
    test-log "\n[test-two-party-services-shape]"
    let tmp = (make-tmp)
    let imgs = {
        platform: "nextcloud:v32",
        receiver_platform: "nextcloud:v32",
        mariadb: "mariadb:11.4",
        valkey: "valkey:7.2",
        mitmproxy: "mitmproxy:v1",
        cypress_ci: "cypress:15",
    }
    emit-cell-images $tmp "stack-7p" $imgs true
    let m = (open ($tmp | path join "meta" "images.v1.json"))
    let svcs = $m.services
    let svc_names = ($svcs | get service)
    let results = [
        (assert-truthy (($tmp | path join "meta" "images.v1.json") | path exists) "meta/images.v1.json exists")
        (assert-eq ($svcs | length) 7 "services length is 7")
        (assert-list-contains $svc_names "sender" "sender present")
        (assert-list-contains $svc_names "receiver" "receiver present")
        (assert-list-contains $svc_names "sender-db" "sender-db present")
        (assert-list-contains $svc_names "receiver-db" "receiver-db present")
        (assert-list-contains $svc_names "sender-cache" "sender-cache present")
        (assert-list-contains $svc_names "receiver-cache" "receiver-cache present")
        (assert-list-contains $svc_names "mitm" "mitm present")
        (assert-list-not-contains $svc_names "cypress" "cypress not in services")
        (assert-list-not-contains $svc_names "cypress_ci" "cypress_ci not in services")
        (assert-list-not-contains $svc_names "cypress_dev" "cypress_dev not in services")
    ]
    let first_cols = ($svcs | first | columns)
    let col_results = [
        (assert-list-contains $first_cols "service" "first entry has service col")
        (assert-list-contains $first_cols "role" "first entry has role col")
        (assert-list-contains $first_cols "tag" "first entry has tag col")
        (assert-list-contains $first_cols "local_image_id" "first entry has local_image_id col")
        (assert-list-contains $first_cols "repo_digests" "first entry has repo_digests col")
        (assert-list-contains $first_cols "digest" "first entry has digest col")
    ]
    let sender_entry = ($svcs | where service == "sender" | first)
    let mitm_entry = ($svcs | where service == "mitm" | first)
    let entry_results = [
        (assert-eq $sender_entry.role "platform" "sender has role=platform")
        (assert-eq $sender_entry.tag "nextcloud:v32" "sender has correct tag")
        (assert-eq $mitm_entry.role "mitmproxy" "mitm has role=mitmproxy")
    ]
    rm -rf $tmp
    $results | append $col_results | append $entry_results
}

# One-party bundle shape: sender + real compose service names, no db/cache.
# bundle_services maps each slot to its actual compose service name; the evidence
# service field must use that, not a synthetic sender-<slot> label.
def test-one-party-bundle-services-shape [] {
    test-log "\n[test-one-party-bundle-services-shape]"
    let tmp = (make-tmp)
    let imgs = {
        platform: "ghcr.io/example/cernbox-web:master",
        bundle: {
            revad: "ghcr.io/example/cernbox-revad:master",
            idp: "ghcr.io/example/idp:v1",
        },
        bundle_services: {
            revad: "sender-revad-gateway",
            idp: "sender-idp",
        },
    }
    emit-cell-images $tmp "stack-bundle-1p" $imgs false
    let m = (open ($tmp | path join "meta" "images.v1.json"))
    let svcs = $m.services
    let svc_names = ($svcs | get service)
    let results = [
        (assert-eq ($svcs | length) 3 "bundle one-party services length is 3")
        (assert-list-contains $svc_names "sender" "sender present")
        (assert-list-contains $svc_names "sender-revad-gateway" "real revad service present")
        (assert-list-contains $svc_names "sender-idp" "real idp service present")
        (assert-list-not-contains $svc_names "sender-revad" "synthetic sender-revad absent")
        (assert-list-not-contains $svc_names "idp" "bare idp service name absent")
        (assert-list-not-contains $svc_names "sender-db" "sender-db absent for bundle")
        (assert-list-not-contains $svc_names "sender-cache" "sender-cache absent for bundle")
    ]
    let revad_entry = ($svcs | where service == "sender-revad-gateway" | first)
    let idp_entry = ($svcs | where service == "sender-idp" | first)
    let entry_results = [
        (assert-eq $revad_entry.role "revad" "revad service role is revad")
        (assert-eq $revad_entry.tag "ghcr.io/example/cernbox-revad:master"
            "revad service tag from bundle")
        (assert-eq $idp_entry.role "idp" "idp service role is idp")
        (assert-eq $idp_entry.tag "ghcr.io/example/idp:v1" "idp service tag from bundle")
    ]
    rm -rf $tmp
    $results | append $entry_results
}

# Bundle slots without bundle_services fall back to the sender-<slot> label.
def test-one-party-bundle-services-fallback [] {
    test-log "\n[test-one-party-bundle-services-fallback]"
    let tmp = (make-tmp)
    let imgs = {
        platform: "ghcr.io/example/cernbox-web:master",
        bundle: {
            revad: "ghcr.io/example/cernbox-revad:master",
        },
    }
    emit-cell-images $tmp "stack-bundle-fallback" $imgs false
    let m = (open ($tmp | path join "meta" "images.v1.json"))
    let svc_names = ($m.services | get service)
    let results = [
        (assert-list-contains $svc_names "sender-revad"
            "fallback uses sender-<slot> when bundle_services absent")
    ]
    rm -rf $tmp
    $results
}

# One-party shape: 3 entries, correct service names.
def test-one-party-services-shape [] {
    test-log "\n[test-one-party-services-shape]"
    let tmp = (make-tmp)
    let imgs = {platform: "nextcloud:v32", mariadb: "mariadb:11.4", valkey: "valkey:7.2"}
    emit-cell-images $tmp "stack-1p" $imgs false
    let m = (open ($tmp | path join "meta" "images.v1.json"))
    let svcs = $m.services
    let svc_names = ($svcs | get service)
    let results = [
        (assert-eq ($svcs | length) 3 "one-party services length is 3")
        (assert-list-contains $svc_names "sender" "sender present")
        (assert-list-contains $svc_names "sender-db" "sender-db present")
        (assert-list-contains $svc_names "sender-cache" "sender-cache present")
    ]
    rm -rf $tmp
    $results
}

# ocmgo platform-only: only sender entry emitted.
def test-ocmgo-platform-only [] {
    test-log "\n[test-ocmgo-platform-only]"
    let tmp = (make-tmp)
    let imgs = {platform: "ocmgo:v1"}
    emit-cell-images $tmp "stack-ocmgo" $imgs false
    let m = (open ($tmp | path join "meta" "images.v1.json"))
    let svcs = $m.services
    let results = [
        (assert-eq ($svcs | length) 1 "ocmgo: only 1 service")
        (assert-eq ($svcs | first).service "sender" "only sender")
        (assert-eq ($svcs | first).role "platform" "role is platform")
        (assert-eq ($svcs | first).tag "ocmgo:v1" "tag is ocmgo:v1")
    ]
    rm -rf $tmp
    $results
}

# Empty tag causes the entry to be skipped.
def test-empty-tag-skipped [] {
    test-log "\n[test-empty-tag-skipped]"
    let tmp = (make-tmp)
    let imgs = {platform: "nextcloud:v32", mariadb: "", valkey: "valkey:7.2"}
    emit-cell-images $tmp "stack-skip" $imgs false
    let m = (open ($tmp | path join "meta" "images.v1.json"))
    let svcs = $m.services
    let svc_names = ($svcs | get service)
    let results = [
        (assert-eq ($svcs | length) 2 "empty tag skipped: length 2")
        (assert-list-contains $svc_names "sender" "sender present")
        (assert-list-contains $svc_names "sender-cache" "sender-cache present")
        (assert-list-not-contains $svc_names "sender-db" "sender-db absent when tag empty")
    ]
    rm -rf $tmp
    $results
}

# Top-level schema fields: version, captured_at, stack_id.
def test-schema-fields [] {
    test-log "\n[test-schema-fields]"
    let tmp = (make-tmp)
    let imgs = {platform: "nextcloud:v32"}
    emit-cell-images $tmp "abc-123" $imgs false
    let m = (open ($tmp | path join "meta" "images.v1.json"))
    let cap = $m.captured_at
    let results = [
        (assert-eq $m.schema_version 1 "schema_version is 1")
        (assert-truthy (($cap | str length) > 19) "captured_at length > 19")
        (assert-eq $m.stack_id "abc-123" "stack_id matches")
        (assert-truthy ($cap =~ '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d+Z$') "captured_at is RFC3339Nano")
    ]
    rm -rf $tmp
    $results
}

def main [] {
    test-log "=== images/emit-cell-images Tests ==="
    let results = (
        (test-two-party-services-shape)
        | append (test-one-party-bundle-services-shape)
        | append (test-one-party-bundle-services-fallback)
        | append (test-one-party-services-shape)
        | append (test-ocmgo-platform-only)
        | append (test-empty-tag-skipped)
        | append (test-schema-fields)
    ) | flatten
    run-suite "images/emit-cell-images" $SUITE_PATH $results
}
