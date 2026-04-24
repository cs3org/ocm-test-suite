# Unit tests for optimize-media and optimizer-probe helpers.
# Run: nu scripts/tests/artifacts/optimize-media.nu
# Returns exit 0 on all pass, exit 1 with details on any failure.

const SUITE_PATH = path self

use ../../lib/artifacts/optimize-media.nu [
    discover-raw-media
    planned-output-items
    run-ffmpeg-convert
    optimize-cell-media
]
use ../../lib/artifacts/optimizer-probe.nu [probe-optimizer-image]
use ../../lib/tests/assert.nu *
use ../../lib/tests/runner.nu [run-suite]

# Short fixture sub-path used in path tests. Represents artifacts/<flow>/<pair>/<exec-id>.
const FX = "artifacts/f/p/e"

# --- discover-raw-media ---

def test-discover-empty [] {
    test-log "\n[test-discover-empty]"
    let id = (random uuid)
    let tmp = $"/tmp/ocmts-test-disc-empty-($id)"
    mkdir $tmp
    let items = (discover-raw-media $tmp)
    try { rm -rf $tmp } catch {}
    [
        (assert-eq ($items | length) 0 "empty artifact root returns no items")
    ]
}

def test-discover-screenshots-and-videos [] {
    test-log "\n[test-discover-screenshots-and-videos]"
    let id = (random uuid)
    let tmp = $"/tmp/ocmts-test-disc-media-($id)"
    mkdir ($tmp | path join $"($FX)/cypress/screenshots")
    mkdir ($tmp | path join $"($FX)/cypress/videos")
    "fake png" | save ($tmp | path join $"($FX)/cypress/screenshots/foo.png")
    "fake png" | save ($tmp | path join $"($FX)/cypress/screenshots/bar.png")
    "fake mp4" | save ($tmp | path join $"($FX)/cypress/videos/baz.mp4")
    let items = (discover-raw-media $tmp)
    try { rm -rf $tmp } catch {}
    let ss = ($items | where kind == "screenshot")
    let vid = ($items | where kind == "video")
    [
        (assert-eq ($items | length) 3 "discovers 3 items total")
        (assert-eq ($ss | length) 2 "discovers 2 screenshots")
        (assert-eq ($vid | length) 1 "discovers 1 video")
    ]
}

def test-discover-screenshot-rel-path [] {
    test-log "\n[test-discover-screenshot-rel-path]"
    let id = (random uuid)
    let tmp = $"/tmp/ocmts-test-disc-rel-($id)"
    mkdir ($tmp | path join $"($FX)/cypress/screenshots")
    "x" | save ($tmp | path join $"($FX)/cypress/screenshots/foo.png")
    let items = (discover-raw-media $tmp)
    try { rm -rf $tmp } catch {}
    [
        (assert-eq
            ($items | first | get rel)
            $"($FX)/cypress/screenshots/foo.png"
            "rel path starts with artifacts/... and is run-relative")
    ]
}

def test-discover-ignores-non-media [] {
    test-log "\n[test-discover-ignores-non-media]"
    let id = (random uuid)
    let tmp = $"/tmp/ocmts-test-disc-ignore-($id)"
    # These paths do not match artifacts/**/cypress/screenshots/**/*.png
    # or artifacts/**/cypress/videos/*.mp4 so they are all ignored.
    mkdir ($tmp | path join $"($FX)/cypress/downloads")
    mkdir ($tmp | path join $"($FX)/docker/logs")
    mkdir ($tmp | path join $"($FX)/meta")
    "x" | save ($tmp | path join $"($FX)/cypress/downloads/file.zip")
    "x" | save ($tmp | path join $"($FX)/docker/logs/sender.log")
    "x" | save ($tmp | path join $"($FX)/meta/run.json")
    let items = (discover-raw-media $tmp)
    try { rm -rf $tmp } catch {}
    [
        (assert-eq ($items | length) 0 "downloads, logs, and meta files are ignored")
    ]
}

# --- planned-output-items ---

def test-planned-screenshot-shape [] {
    test-log "\n[test-planned-screenshot-shape]"
    let src = $"($FX)/cypress/screenshots/foo.png"
    let items = (planned-output-items $src "screenshot")
    let primary = ($items | where role == "primary" | first)
    let fallback = ($items | where role == "fallback" | first)
    [
        (assert-eq ($items | length) 2 "screenshot produces 2 items")
        (assert-eq $primary.optimized_path $"($FX)/cypress/screenshots/foo.avif" "primary is AVIF")
        (assert-eq $primary.format "avif" "primary format field")
        (assert-eq $primary.mime "image/avif" "primary mime field")
        (assert-eq $primary.kind "screenshot" "primary kind field")
        (assert-eq $primary.status "optimized" "primary status field")
        (assert-eq $primary.source_path $src "primary source_path")
        (assert-eq $fallback.optimized_path $"($FX)/cypress/screenshots/foo.webp" "fallback is WebP")
        (assert-eq $fallback.format "webp" "fallback format field")
        (assert-eq $fallback.mime "image/webp" "fallback mime field")
        (assert-eq $fallback.role "fallback" "fallback role field")
    ]
}

def test-planned-video-shape [] {
    test-log "\n[test-planned-video-shape]"
    let src = $"($FX)/cypress/videos/bar.mp4"
    let items = (planned-output-items $src "video")
    let primary = ($items | where role == "primary" | first)
    let fallback = ($items | where role == "fallback" | first)
    [
        (assert-eq ($items | length) 2 "video produces 2 items")
        (assert-eq $primary.optimized_path $"($FX)/cypress/videos/bar.av1.webm" "primary is AV1 WebM")
        (assert-eq $primary.format "av1-webm" "primary format field")
        (assert-eq $primary.mime "video/webm" "primary mime is video/webm")
        (assert-eq ($primary.codecs? | default "") "av01" "primary codecs is av01")
        (assert-eq $fallback.optimized_path $"($FX)/cypress/videos/bar.vp9.webm" "fallback is VP9 WebM")
        (assert-eq $fallback.format "vp9-webm" "fallback format field")
        (assert-eq $fallback.mime "video/webm" "fallback mime is video/webm")
        (assert-eq ($fallback.codecs? | default "") "vp9" "fallback codecs is vp9")
    ]
}

def test-planned-nested-screenshot [] {
    test-log "\n[test-planned-nested-screenshot]"
    let src = $"($FX)/cypress/screenshots/sub/deep.png"
    let items = (planned-output-items $src "screenshot")
    let primary = ($items | where role == "primary" | first)
    let fallback = ($items | where role == "fallback" | first)
    [
        (assert-eq $primary.optimized_path $"($FX)/cypress/screenshots/sub/deep.avif" "nested AVIF path preserved")
        (assert-eq $fallback.optimized_path $"($FX)/cypress/screenshots/sub/deep.webp" "nested WebP path preserved")
        (assert-eq $primary.source_path $src "source_path preserved")
    ]
}

def test-planned-source-path-preserved [] {
    test-log "\n[test-planned-source-path-preserved]"
    let src = $"($FX)/cypress/screenshots/login__opencloud-v6--001--single--done.png"
    let items = (planned-output-items $src "screenshot")
    [
        (assert-eq ($items | all {|r| $r.source_path == $src}) true "source_path is same in all items")
    ]
}

def test-planned-screenshot-no-codecs [] {
    test-log "\n[test-planned-screenshot-no-codecs]"
    let src = $"($FX)/cypress/screenshots/foo.png"
    let items = (planned-output-items $src "screenshot")
    [
        (assert-eq ($items | all {|r| ($r.codecs? == null)}) true "screenshot items have no codecs field")
    ]
}

def test-planned-video-has-codecs [] {
    test-log "\n[test-planned-video-has-codecs]"
    let src = $"($FX)/cypress/videos/bar.mp4"
    let items = (planned-output-items $src "video")
    let primary = ($items | where role == "primary" | first)
    let fallback = ($items | where role == "fallback" | first)
    [
        (assert-truthy (($primary.codecs? | default "") != "") "video primary item has codecs field")
        (assert-truthy (($fallback.codecs? | default "") != "") "video fallback item has codecs field")
    ]
}

# --- zero-media cell (no docker required) ---

def test-zero-media-manifest [] {
    test-log "\n[test-zero-media-manifest]"
    let id = (random uuid)
    let raw_tmp = $"/tmp/ocmts-test-zero-raw-($id)"
    let out_tmp = $"/tmp/ocmts-test-zero-out-($id)"
    # Create the artifact root structure but with no media files.
    mkdir ($raw_tmp | path join $"($FX)/cypress/screenshots")
    mkdir ($raw_tmp | path join $"($FX)/cypress/videos")
    mkdir ($raw_tmp | path join $"($FX)/meta")
    let result = (optimize-cell-media $raw_tmp $out_tmp "fake-image:latest")
    let manifest_path = ($out_tmp | path join "meta/optimized-media-cell.v1.json")
    let manifest_exists = ($manifest_path | path exists)
    let manifest = if $manifest_exists { open $manifest_path } else { {} }
    try { rm -rf $raw_tmp } catch {}
    try { rm -rf $out_tmp } catch {}
    [
        (assert-eq $result.status "no-source-media" "result status is no-source-media")
        (assert-eq ($result.items | length) 0 "result has no items")
        (assert-truthy $manifest_exists "manifest file written to out_dir/meta/")
        (assert-eq ($manifest.status? | default "") "no-source-media" "manifest status field")
        (assert-eq ($manifest.schema_version? | default 0) 1 "manifest schema_version is 1")
        (assert-eq ($manifest.items? | default [] | length) 0 "manifest items is empty list")
        (assert-truthy (not ($manifest.generated_at? | default "" | is-empty)) "manifest has generated_at")
        (assert-truthy (not ($manifest.optimizer_image? | default "" | is-empty)) "manifest has optimizer_image")
    ]
}

# --- probe structure (image availability not required) ---

def test-probe-structure-unavailable [] {
    test-log "\n[test-probe-structure-unavailable]"
    let probe = (probe-optimizer-image "ocmts-nonexistent-image-for-test:latest")
    [
        (assert-truthy (($probe | columns | length) > 0) "probe returns a record")
        (assert-truthy ("ok" in ($probe | columns)) "probe has ok field")
        (assert-truthy ("available" in ($probe | columns)) "probe has available field")
        (assert-truthy ("encoders" in ($probe | columns)) "probe has encoders field")
        (assert-truthy ("muxers" in ($probe | columns)) "probe has muxers field")
        (assert-truthy ("image" in ($probe | columns)) "probe has image field")
        (assert-eq $probe.ok false "probe.ok is false for unavailable image")
        (assert-eq $probe.available false "probe.available is false for missing image")
    ]
}

def main [] {
    let results = (
        (test-discover-empty)
        | append (test-discover-screenshots-and-videos)
        | append (test-discover-screenshot-rel-path)
        | append (test-discover-ignores-non-media)
        | append (test-planned-screenshot-shape)
        | append (test-planned-video-shape)
        | append (test-planned-nested-screenshot)
        | append (test-planned-source-path-preserved)
        | append (test-planned-screenshot-no-codecs)
        | append (test-planned-video-has-codecs)
        | append (test-zero-media-manifest)
        | append (test-probe-structure-unavailable)
    )
    run-suite "artifacts/optimize-media" $SUITE_PATH $results
}
