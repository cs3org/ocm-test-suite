# Public CLI regression tests for `services list-cell-images`.
# Run: nu scripts/tests/cli/list-cell-images.nu
# Proves bundle refs are emitted on the real command path after resolve-images
# bundle reduction, and that non-bundle tuples keep the prior line shape.

const SUITE_PATH = path self

use ../../lib/images/resolve.nu [
    resolve-images
    resolve-receiver-images
    resolve-mitmproxy-image
]
use ../../lib/matrix/cell.nu [compute-cell]
use ../../lib/tests/assert.nu *
use ../../lib/tests/runner.nu [run-suite]

const SEEDED_OVERRIDE_REF = "ghcr.io/example/ocmts-test:seeded-override"

def repo-root [] {
    $SUITE_PATH | path dirname | path dirname | path dirname | path dirname
}

def ocmts-script [] {
    (repo-root) | path join "scripts/ocmts.nu"
}

def seeded-image-env [keys: list<string>] {
    $keys | reduce --fold {} {|k, acc|
        $acc | upsert $k $SEEDED_OVERRIDE_REF
    }
}

def cleared-image-env-mask [keys: list<string>] {
    $keys | reduce --fold {} {|k, acc|
        $acc | upsert $k null
    }
}

def cernbox-image-env-mask [] {
    cleared-image-env-mask [
        OCMTS_CERNBOX_WEB_V11_IMAGE
        OCMTS_CERNBOX_REVAD_IMAGE
        OCMTS_CERNBOX_IDP_IMAGE
        OCMTS_CYPRESS_CI_IMAGE
        OCMTS_MARIADB_IMAGE
        OCMTS_VALKEY_IMAGE
    ]
}

def share-with-cernbox-image-env-mask [] {
    (cernbox-image-env-mask)
    | merge (cleared-image-env-mask [OCMTS_MITMPROXY_IMAGE])
}

def link-path [src: string, dest: string] {
    mkdir ($dest | path dirname)
    ^ln -sf $src $dest
}

# Minimal config-root fixture: share-with matrix tuple cernbox/cernbox only.
def write-share-with-cernbox-fixture-root [real_root: string, fixture_root: string] {
    let cfg = ($fixture_root | path join "config")
    let matrix_flows = ($cfg | path join "matrix" "flows")
    mkdir $matrix_flows

    link-path ($real_root | path join "config" "images.nuon") ($cfg | path join "images.nuon")
    link-path ($real_root | path join "config" "matrix" "defaults.nuon") ($cfg | path join "matrix" "defaults.nuon")
    link-path ($real_root | path join "config" "matrix" "platforms.nuon") ($cfg | path join "matrix" "platforms.nuon")
    link-path ($real_root | path join "config" "matrix" "capabilities.v1.nuon") ($cfg | path join "matrix" "capabilities.v1.nuon")
    for flow in [login contact-wayf contact-token] {
        link-path ($real_root | path join "config" "matrix" "flows" $"($flow).nuon") ($matrix_flows | path join $"($flow).nuon")
    }
    link-path ($real_root | path join "scripts") ($fixture_root | path join "scripts")

    let share_with = (open ($real_root | path join "config/matrix/flows/share-with.nuon"))
    let share_with_cernbox = (
        $share_with
        | upsert include (
            $share_with.include
            | append {sender: ["cernbox"], receiver: ["cernbox"], version_pairing: "cross_product"}
        )
        | upsert versions_sender ($share_with.versions_sender | upsert cernbox ["v11"])
        | upsert versions_receiver ($share_with.versions_receiver | upsert cernbox ["v11"])
    )
    $share_with_cernbox | to nuon | save --force ($matrix_flows | path join "share-with.nuon")
}

def nextcloud-image-env-mask [] {
    cleared-image-env-mask [
        OCMTS_NEXTCLOUD_V32_IMAGE
        OCMTS_NEXTCLOUD_V32_SENDER_IMAGE
        OCMTS_NEXTCLOUD_V32_RECEIVER_IMAGE
        OCMTS_CYPRESS_CI_IMAGE
        OCMTS_MARIADB_IMAGE
        OCMTS_VALKEY_IMAGE
    ]
}

def resolve-one-party-images [
    flow: string,
    platform: string,
    version: string,
] {
    let cell = (compute-cell $flow $platform $version "chrome")
    (
        resolve-images $platform $version
            --matrix-key $cell.matrix_key
            --flow-id $cell.flow_id
    )
}

def expected-one-party-base-refs [
    flow: string,
    platform: string,
    version: string,
] {
    let imgs = (resolve-one-party-images $flow $platform $version)
    [$imgs.platform $imgs.cypress_ci $imgs.mariadb $imgs.valkey] | sort
}

def resolve-two-party-cernbox-images [
    flow: string,
    sender_version: string,
    receiver_version: string,
] {
    let cell = (compute-cell $flow "cernbox" $sender_version "chrome" "cernbox" $receiver_version)
    let sender_imgs = (
        resolve-images "cernbox" $sender_version
            --matrix-key $cell.matrix_key
            --flow-id $cell.flow_id
    )
    let recv_imgs = (
        resolve-receiver-images "cernbox" $receiver_version
            --matrix-key $cell.matrix_key
            --flow-id $cell.flow_id
    )
    let mitm_img = (
        resolve-mitmproxy-image --matrix-key $cell.matrix_key --flow-id $cell.flow_id
    )
    {
        cell: $cell
        sender_imgs: $sender_imgs
        recv_imgs: $recv_imgs
        mitm_img: $mitm_img
    }
}

def run-list-cell-images [cmd_args: list<string>, env_mask: record = {}] {
    with-env $env_mask {
        (^nu (ocmts-script) services list-cell-images ...$cmd_args | complete)
    }
}

def parse-image-lines [out: record] {
    $out.stdout
    | lines
    | each {|l| $l | str trim }
    | where {|l| not ($l | is-empty) }
}

def assert-unique-one-ref-per-line [lines: list<string>, label: string] {
    let nonempty = ($lines | all {|l| ($l | str length) > 0 })
    let no_whitespace = ($lines | all {|l| not ($l | str contains " ") })
    let deduped = (($lines | length) == ($lines | uniq | length))
    [
        (assert-truthy $nonempty $"($label): every line is a non-empty image ref")
        (assert-truthy $no_whitespace $"($label): every line is one image ref without spaces")
        (assert-truthy $deduped $"($label): output is deduplicated")
    ]
}

def test-list-cell-images-cernbox-bundle-refs [] {
    test-log "\n[test-list-cell-images-cernbox-bundle-refs]"
    let mask = (cernbox-image-env-mask)
    let state = (
        with-env (seeded-image-env [
            OCMTS_CERNBOX_WEB_V11_IMAGE
            OCMTS_CERNBOX_REVAD_IMAGE
        ]) {
            let out = (
                run-list-cell-images [
                    --flow login
                    --sender-platform cernbox
                    --sender-version v11
                ] $mask
            )
            let lines = (parse-image-lines $out)
            let imgs = (
                with-env $mask {
                    resolve-one-party-images "login" "cernbox" "v11"
                }
            )
            let bundle_refs = ($imgs.bundle | values)
            let base_refs = [
                $imgs.platform
                $imgs.cypress_ci
                $imgs.mariadb
                $imgs.valkey
            ]
            let unique_expected = ($base_refs | append $bundle_refs | uniq)
            {
                out: $out
                lines: $lines
                imgs: $imgs
                bundle_refs: $bundle_refs
                base_refs: $base_refs
                unique_expected: $unique_expected
            }
        }
    )
    let out = $state.out
    let lines = $state.lines
    let imgs = $state.imgs
    let bundle_refs = $state.bundle_refs
    let base_refs = $state.base_refs
    let unique_expected = $state.unique_expected
    [
        (assert-eq $out.exit_code 0
            "list-cell-images cernbox bundle exits 0")
        (assert-truthy ($bundle_refs | all {|r| $r in $lines})
            "list-cell-images cernbox bundle emits every resolve-images bundle ref")
        (assert-truthy (($imgs.bundle | get revad) in $lines)
            "list-cell-images cernbox bundle emits revad on CLI path")
        (assert-truthy (($imgs.bundle | get idp) in $lines)
            "list-cell-images cernbox bundle emits idp on CLI path")
        (assert-truthy ($base_refs | all {|r| $r in $lines})
            "list-cell-images cernbox bundle emits base cell refs")
        (assert-eq ($lines | length) ($unique_expected | length)
            "list-cell-images cernbox bundle emits expected unique ref count")
        (assert-eq ($lines | sort) ($unique_expected | sort)
            "list-cell-images cernbox bundle output matches resolve-images ref set")
    ]
    | append (assert-unique-one-ref-per-line $lines "list-cell-images cernbox bundle")
}

def test-list-cell-images-nextcloud-non-bundle [] {
    test-log "\n[test-list-cell-images-nextcloud-non-bundle]"
    let mask = (nextcloud-image-env-mask)
    let state = (
        with-env (seeded-image-env [
            OCMTS_NEXTCLOUD_V32_IMAGE
            OCMTS_CYPRESS_CI_IMAGE
        ]) {
            let out = (
                run-list-cell-images [
                    --flow login
                    --sender-platform nextcloud
                    --sender-version v32
                ] $mask
            )
            let lines = (parse-image-lines $out)
            let want = (
                with-env $mask {
                    expected-one-party-base-refs "login" "nextcloud" "v32"
                }
            )
            {
                out: $out
                lines: $lines
                want: $want
            }
        }
    )
    let out = $state.out
    let lines = $state.lines
    let want = $state.want
    let bundle_only = (
        with-env (cernbox-image-env-mask) {
            (resolve-images "cernbox" "v11").bundle | values
        }
    )
    [
        (assert-eq $out.exit_code 0
            "list-cell-images nextcloud non-bundle exits 0")
        (assert-eq ($lines | length) ($want | length)
            "list-cell-images nextcloud non-bundle emits expected ref count")
        (assert-eq ($lines | sort) $want
            "list-cell-images nextcloud non-bundle output shape unchanged")
        (assert-truthy (not ($lines | any {|l| $l in $bundle_only}))
            "list-cell-images nextcloud non-bundle omits bundle-only refs")
    ]
    | append (assert-unique-one-ref-per-line $lines "list-cell-images nextcloud non-bundle")
}

def test-list-cell-images-two-party-cernbox-receiver-bundle-refs [] {
    test-log "\n[test-list-cell-images-two-party-cernbox-receiver-bundle-refs]"
    let real_root = (repo-root)
    let fixture_root = ($nu.temp-dir | path join $"cli-list-cell-images-2p-(random uuid)")
    write-share-with-cernbox-fixture-root $real_root $fixture_root
    let mask = (share-with-cernbox-image-env-mask)
    let state = (
        with-env (
            seeded-image-env [
                OCMTS_CERNBOX_WEB_V11_IMAGE
                OCMTS_CERNBOX_REVAD_IMAGE
                OCMTS_CERNBOX_IDP_IMAGE
                OCMTS_MITMPROXY_IMAGE
            ]
            | merge {OCMTS_ROOT: $fixture_root}
        ) {
            let out = (
                run-list-cell-images [
                    --flow share-with
                    --sender-platform cernbox
                    --sender-version v11
                    --receiver-platform cernbox
                    --receiver-version v11
                ] $mask
            )
            let lines = (parse-image-lines $out)
            let resolved = (
                with-env $mask {
                    resolve-two-party-cernbox-images "share-with" "v11" "v11"
                }
            )
            let sender_imgs = $resolved.sender_imgs
            let recv_imgs = $resolved.recv_imgs
            let sender_bundle_refs = ($sender_imgs.bundle | values)
            let recv_bundle_refs = ($recv_imgs.bundle | values)
            let base_refs = [
                $sender_imgs.platform
                $sender_imgs.cypress_ci
                $sender_imgs.mariadb
                $sender_imgs.valkey
            ]
            let two_party_refs = [
                $recv_imgs.platform
                $resolved.mitm_img
            ]
            let unique_expected = (
                $base_refs
                | append $sender_bundle_refs
                | append $two_party_refs
                | append $recv_bundle_refs
                | uniq
            )
            {
                out: $out
                lines: $lines
                sender_imgs: $sender_imgs
                recv_imgs: $recv_imgs
                mitm_img: $resolved.mitm_img
                base_refs: $base_refs
                recv_bundle_refs: $recv_bundle_refs
                two_party_refs: $two_party_refs
                unique_expected: $unique_expected
            }
        }
    )
    let out = $state.out
    let lines = $state.lines
    let sender_imgs = $state.sender_imgs
    let recv_imgs = $state.recv_imgs
    let mitm_img = $state.mitm_img
    let base_refs = $state.base_refs
    let recv_bundle_refs = $state.recv_bundle_refs
    let two_party_refs = $state.two_party_refs
    let unique_expected = $state.unique_expected
    let results = [
        (assert-eq $out.exit_code 0
            "list-cell-images two-party cernbox receiver bundle exits 0")
        (assert-truthy ($two_party_refs | all {|r| $r in $lines})
            "list-cell-images two-party cernbox emits receiver platform and mitmproxy")
        (assert-truthy ($recv_imgs.platform in $lines)
            "list-cell-images two-party cernbox emits receiver platform on CLI path")
        (assert-truthy ($mitm_img in $lines)
            "list-cell-images two-party cernbox emits mitmproxy on CLI path")
        (assert-truthy ($recv_bundle_refs | all {|r| $r in $lines})
            "list-cell-images two-party cernbox emits every resolve-receiver-images bundle ref")
        (assert-truthy (($recv_imgs.bundle | get revad) in $lines)
            "list-cell-images two-party cernbox emits receiver revad on CLI path")
        (assert-truthy (($recv_imgs.bundle | get idp) in $lines)
            "list-cell-images two-party cernbox emits receiver idp on CLI path")
        (assert-truthy ($base_refs | all {|r| $r in $lines})
            "list-cell-images two-party cernbox emits sender base cell refs")
        (assert-truthy ($sender_imgs.bundle | values | all {|r| $r in $lines})
            "list-cell-images two-party cernbox emits sender bundle refs")
        (assert-eq ($lines | length) ($unique_expected | length)
            "list-cell-images two-party cernbox emits expected unique ref count")
        (assert-eq ($lines | sort) ($unique_expected | sort)
            "list-cell-images two-party cernbox output matches resolved ref set")
    ]
    | append (assert-unique-one-ref-per-line $lines "list-cell-images two-party cernbox receiver bundle")
    rm -rf $fixture_root
    $results
}

def main [] {
    test-log "=== cli/list-cell-images tests ==="
    let results = (
        (test-list-cell-images-cernbox-bundle-refs)
        | append (test-list-cell-images-nextcloud-non-bundle)
        | append (test-list-cell-images-two-party-cernbox-receiver-bundle-refs)
    ) | flatten
    run-suite "cli/list-cell-images" $SUITE_PATH $results
}
