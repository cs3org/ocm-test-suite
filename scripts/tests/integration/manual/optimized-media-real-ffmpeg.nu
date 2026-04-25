# Manual e2e test. Requires Docker + network for first-time image pull.
# Excluded from `nu scripts/tests/run-all.nu` via the manual/ subdir gate.
# Run directly: nu scripts/tests/integration/manual/optimized-media-real-ffmpeg.nu

const SUITE_PATH = path self

use ../../../lib/images/resolve.nu [resolve-media-optimizer-image]
use ../../../lib/artifacts/optimizer-probe.nu [probe-optimizer-image]
use ../../../lib/artifacts/optimize-media.nu [optimize-cell-media]
use ../../../lib/tests/assert.nu *
use ../../../lib/tests/runner.nu [run-suite]

def get-fixtures-dir []: nothing -> string {
    # SUITE_PATH = .../scripts/tests/integration/manual/optimized-media-real-ffmpeg.nu
    # Repo root = 5 dirname hops (manual -> integration -> tests -> scripts -> repo root)
    let repo_root = (
        $SUITE_PATH | path dirname | path dirname | path dirname | path dirname | path dirname
    )
    $repo_root | path join "scripts/tests/fixtures/optimized-media"
}

def assert-bytes-start-hex [path: string, hex: string, label: string] {
    let bytes = (open --raw $path)
    let want_len = (($hex | str length) // 2)
    let prefix = ($bytes | bytes at 0..($want_len - 1))
    let actual = ($prefix | encode hex | str downcase)
    if $actual == ($hex | str downcase) {
        if ($env.OCMTS_TEST_JSON? != "1") { print $"  ok: ($label)" }
        PASS
    } else {
        if ($env.OCMTS_TEST_JSON? != "1") {
            print $"  FAIL: ($label) - want hex prefix ($hex), got ($actual)"
        }
        FAIL $label
    }
}

def assert-bytes-at-hex [path: string, offset: int, hex: string, label: string] {
    let bytes = (open --raw $path)
    let want_len = (($hex | str length) // 2)
    let slice = ($bytes | bytes at $offset..($offset + $want_len - 1))
    let actual = ($slice | encode hex | str downcase)
    if $actual == ($hex | str downcase) {
        if ($env.OCMTS_TEST_JSON? != "1") { print $"  ok: ($label)" }
        PASS
    } else {
        if ($env.OCMTS_TEST_JSON? != "1") {
            print $"  FAIL: ($label) - want hex at offset ($offset) = ($hex), got ($actual)"
        }
        FAIL $label
    }
}

# --- test-real-probe-optimizer ---

def test-real-probe-optimizer [] {
    test-log "\n[test-real-probe-optimizer]"
    let img = (resolve-media-optimizer-image)
    let probe = (probe-optimizer-image $img)
    [
        (assert-truthy $probe.ok "probe.ok is true")
        (assert-truthy $probe.encoders.libwebp "probe.encoders.libwebp is true")
        (assert-truthy $probe.encoders.libaom_av1 "probe.encoders.libaom_av1 is true")
        (assert-truthy $probe.encoders.libvpx_vp9 "probe.encoders.libvpx_vp9 is true")
        (assert-truthy $probe.muxers.avif "probe.muxers.avif is true")
        (assert-truthy $probe.muxers.webp "probe.muxers.webp is true")
        (assert-truthy $probe.muxers.webm "probe.muxers.webm is true")
    ]
}

# --- test-real-png-to-avif-and-webp ---

def test-real-png-to-avif-and-webp [] {
    test-log "\n[test-real-png-to-avif-and-webp]"
    let work = (^mktemp -d | str trim)
    let fixtures = (get-fixtures-dir)
    let img = (resolve-media-optimizer-image)
    let run_sub = "artifacts/login/nextcloud-v34/exec-fixture"

    # Stage the full raw-input tree.
    ^cp -r ($fixtures | path join "raw-input") ($work | path join "raw")

    optimize-cell-media ($work | path join "raw") ($work | path join "out") $img

    let out_base = ($work | path join "out" | path join $run_sub | path join "cypress/screenshots")
    let avif = ($out_base | path join "sample.avif")
    let webp = ($out_base | path join "sample.webp")

    let avif_exists = ($avif | path exists)
    let webp_exists = ($webp | path exists)

    let avif_ftyp = if $avif_exists { (assert-bytes-at-hex $avif 4 "66747970" "AVIF starts with ftyp box") } else { FAIL "sample.avif does not exist" }
    let webp_riff = if $webp_exists { (assert-bytes-start-hex $webp "52494646" "WebP starts with RIFF") } else { FAIL "sample.webp does not exist" }
    let webp_webp = if $webp_exists { (assert-bytes-at-hex $webp 8 "57454250" "WebP RIFF type is WEBP") } else { FAIL "sample.webp WEBP check skipped" }

    ^rm -rf $work
    [
        (assert-truthy $avif_exists "sample.avif produced")
        (assert-truthy $webp_exists "sample.webp produced")
        $avif_ftyp
        $webp_riff
        $webp_webp
    ]
}

# --- test-real-mp4-to-av1-webm-and-vp9-webm ---

def test-real-mp4-to-av1-webm-and-vp9-webm [] {
    test-log "\n[test-real-mp4-to-av1-webm-and-vp9-webm]"
    let work = (^mktemp -d | str trim)
    let fixtures = (get-fixtures-dir)
    let img = (resolve-media-optimizer-image)
    let run_sub = "artifacts/login/nextcloud-v34/exec-fixture"

    # Stage the full raw-input tree into a fresh temp dir.
    ^cp -r ($fixtures | path join "raw-input") ($work | path join "raw")

    optimize-cell-media ($work | path join "raw") ($work | path join "out") $img

    let out_base = ($work | path join "out" | path join $run_sub | path join "cypress/videos")
    let av1 = ($out_base | path join "sample.av1.webm")
    let vp9 = ($out_base | path join "sample.vp9.webm")

    let av1_exists = ($av1 | path exists)
    let vp9_exists = ($vp9 | path exists)

    let av1_ebml = if $av1_exists { (assert-bytes-start-hex $av1 "1a45dfa3" "AV1 WebM has EBML magic") } else { FAIL "sample.av1.webm does not exist" }
    let vp9_ebml = if $vp9_exists { (assert-bytes-start-hex $vp9 "1a45dfa3" "VP9 WebM has EBML magic") } else { FAIL "sample.vp9.webm does not exist" }

    ^rm -rf $work
    [
        (assert-truthy $av1_exists "sample.av1.webm produced")
        (assert-truthy $vp9_exists "sample.vp9.webm produced")
        $av1_ebml
        $vp9_ebml
    ]
}

def main [] {
    test-log "=== integration/manual/optimized-media-real-ffmpeg tests ==="
    let results = (
        (test-real-probe-optimizer)
        | append (test-real-png-to-avif-and-webp)
        | append (test-real-mp4-to-av1-webm-and-vp9-webm)
    ) | flatten
    run-suite "integration/manual/optimized-media-real-ffmpeg" $SUITE_PATH $results
}
