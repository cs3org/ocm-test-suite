# Integration tests for the optimized media pipeline end-to-end.
# Covers: aggregate -> project round-trip, no-media cell, gate logic, empty agg.
# Run: nu scripts/tests/integration/optimized-media-pipeline.nu

const SUITE_PATH = path self

use ../../lib/site/project-media.nu [
    apply-media-projection
    manifest-has-media-rows
]
use ../../lib/artifacts/aggregate-optimized-media.nu [aggregate-optimized-media-cells]
use ../../lib/tests/assert.nu *
use ../../lib/tests/runner.nu [run-suite]

def get-repo-root []: nothing -> string {
    # SUITE_PATH = .../scripts/tests/integration/optimized-media-pipeline.nu
    # Repo root = 4 dirname hops (integration -> tests -> scripts -> repo root)
    $SUITE_PATH | path dirname | path dirname | path dirname | path dirname
}

def get-fixtures-dir []: nothing -> string {
    (get-repo-root) | path join "scripts/tests/fixtures/optimized-media"
}

# --- full round-trip: aggregate then project ---

def test-e2e-aggregate-then-project-success [] {
    test-log "\n[test-e2e-aggregate-then-project-success]"
    let work = (^mktemp -d | str trim)
    let fixtures = (get-fixtures-dir)
    let run_prefix = "artifacts/login/nextcloud-v34/exec-fixture"

    # Copy pre-optimized cell into a cell dir that aggregate-optimized-media-cells can read.
    mkdir ($work | path join "cells")
    ^cp -r ($fixtures | path join "pre-optimized") ($work | path join "cells/cell-fixture")

    # Aggregate the cell.
    let cell_dir = ($work | path join "cells/cell-fixture")
    aggregate-optimized-media-cells [$cell_dir] ($work | path join "agg") --no-archive

    # Set up pub dir.
    mkdir ($work | path join "pub")
    ^cp ($fixtures | path join "raw-public-manifest.json") ($work | path join "pub/suite-manifest.v1.json")

    # Create raw marker files in pub so the remove step has something to remove.
    mkdir ($work | path join "pub" | path join $run_prefix | path join "cypress/screenshots")
    mkdir ($work | path join "pub" | path join $run_prefix | path join "cypress/videos")
    "marker" | save -f ($work | path join "pub" | path join $run_prefix | path join "cypress/screenshots/sample.png")
    "marker" | save -f ($work | path join "pub" | path join $run_prefix | path join "cypress/videos/sample.mp4")

    # Project.
    apply-media-projection ($work | path join "pub") ($work | path join "agg")

    # Read projected manifest.
    let projected = (open ($work | path join "pub/suite-manifest.v1.json"))
    let result = $projected.results.result-exec-fixture
    let ss_ev = ($result.evidence | where kind == "screenshot" | first)
    let vid_ev = ($result.evidence | where kind == "video" | first)

    let ss_variants = ($ss_ev.media_variants? | default [])
    let vid_variants = ($vid_ev.media_variants? | default [])

    let base = ($work | path join "pub" | path join $run_prefix)
    let avif_exists = (($base | path join "cypress/screenshots/sample.avif") | path exists)
    let webp_exists = (($base | path join "cypress/screenshots/sample.webp") | path exists)
    let av1_exists = (($base | path join "cypress/videos/sample.av1.webm") | path exists)
    let vp9_exists = (($base | path join "cypress/videos/sample.vp9.webm") | path exists)
    let png_gone = not (($base | path join "cypress/screenshots/sample.png") | path exists)
    let mp4_gone = not (($base | path join "cypress/videos/sample.mp4") | path exists)

    ^rm -rf $work
    [
        (assert-truthy ($ss_ev.path | str ends-with ".avif") "screenshot path ends with .avif")
        (assert-truthy ($ss_ev.source_path | str ends-with ".png") "screenshot source_path ends with .png")
        (assert-eq ($ss_variants | length) 2 "screenshot has 2 media_variants")
        (assert-eq ($ss_variants | first).role "primary" "screenshot primary variant is first")
        (assert-eq ($ss_variants | first).format "avif" "screenshot primary format is avif")
        (assert-eq ($ss_variants | first).mime "image/avif" "screenshot primary mime is image/avif")
        (assert-eq ($ss_variants | last).role "fallback" "screenshot fallback variant is second")
        (assert-eq ($ss_variants | last).format "webp" "screenshot fallback format is webp")
        (assert-eq ($ss_variants | last).mime "image/webp" "screenshot fallback mime is image/webp")
        (assert-truthy ($vid_ev.path | str ends-with ".av1.webm") "video path ends with .av1.webm")
        (assert-truthy ($vid_ev.source_path | str ends-with ".mp4") "video source_path ends with .mp4")
        (assert-eq ($vid_variants | length) 2 "video has 2 media_variants")
        (assert-eq ($vid_variants | first).role "primary" "video primary variant is first")
        (assert-eq ($vid_variants | first).format "av1-webm" "video primary format is av1-webm")
        (assert-eq ($vid_variants | first).mime "video/webm" "video primary mime is video/webm")
        (assert-eq ($vid_variants | first).codecs "av01" "video primary codecs is av01")
        (assert-eq ($vid_variants | last).role "fallback" "video fallback variant is second")
        (assert-eq ($vid_variants | last).format "vp9-webm" "video fallback format is vp9-webm")
        (assert-eq ($vid_variants | last).mime "video/webm" "video fallback mime is video/webm")
        (assert-eq ($vid_variants | last).codecs "vp9" "video fallback codecs is vp9")
        (assert-truthy $avif_exists "sample.avif copied to pub artifacts tree")
        (assert-truthy $webp_exists "sample.webp copied to pub artifacts tree")
        (assert-truthy $av1_exists "sample.av1.webm copied to pub artifacts tree")
        (assert-truthy $vp9_exists "sample.vp9.webm copied to pub artifacts tree")
        (assert-truthy $png_gone "sample.png removed from pub artifacts tree")
        (assert-truthy $mp4_gone "sample.mp4 removed from pub artifacts tree")
    ]
}

# --- aggregate with no-source-media cell ---

def test-e2e-no-source-media-cell [] {
    test-log "\n[test-e2e-no-source-media-cell]"
    let work = (^mktemp -d | str trim)
    let fixtures = (get-fixtures-dir)

    mkdir ($work | path join "cells")
    ^cp -r ($fixtures | path join "pre-optimized-no-media") ($work | path join "cells/blocked-cell")

    let blocked_dir = ($work | path join "cells/blocked-cell")
    let result = (
        aggregate-optimized-media-cells [$blocked_dir] ($work | path join "agg") --no-archive
    )

    let summary = (open ($work | path join "agg/meta/optimized-media-summary.v1.json"))
    let ic_cols = ($summary.item_counts | columns)

    ^rm -rf $work
    [
        (assert-eq $result.cells_found 1 "cells_found == 1")
        (assert-eq $result.cells_with_media 0 "cells_with_media == 0")
        (assert-eq $result.cells_without_media 1 "cells_without_media == 1")
        (assert-eq $result.cells_missing_manifest 0 "cells_missing_manifest == 0")
        (assert-eq $result.optimized_item_count 0 "optimized_item_count == 0")
        (assert-eq $result.failed_item_count 0 "failed_item_count == 0")
        (assert-eq $summary.cell_counts_by_status.no_source_media 1 "summary.cell_counts_by_status.no_source_media == 1")
        (assert-eq $summary.cell_counts_by_status.missing_manifest 0 "summary.cell_counts_by_status.missing_manifest == 0")
        (assert-eq $summary.item_counts.optimized 0 "summary.item_counts.optimized == 0")
        (assert-eq $summary.item_counts.failed 0 "summary.item_counts.failed == 0")
        (assert-truthy (not ("no_source_media" in $ic_cols))
            "item_counts does not have no_source_media key")
    ]
}

# --- apply-media-projection fails on empty opt dir ---

def test-e2e-publish-fails-on-empty-opt-dir-with-media [] {
    test-log "\n[test-e2e-publish-fails-on-empty-opt-dir-with-media]"
    let work = (^mktemp -d | str trim)
    let fixtures = (get-fixtures-dir)
    let run_prefix = "artifacts/login/nextcloud-v34/exec-fixture"

    mkdir ($work | path join "pub")
    ^cp ($fixtures | path join "raw-public-manifest.json") ($work | path join "pub/suite-manifest.v1.json")

    # Create raw markers.
    mkdir ($work | path join "pub" | path join $run_prefix | path join "cypress/screenshots")
    mkdir ($work | path join "pub" | path join $run_prefix | path join "cypress/videos")
    "marker" | save -f ($work | path join "pub" | path join $run_prefix | path join "cypress/screenshots/sample.png")
    "marker" | save -f ($work | path join "pub" | path join $run_prefix | path join "cypress/videos/sample.mp4")

    # Empty aggregate dir (exists but no optimized files).
    mkdir ($work | path join "agg-empty")

    let err_msg = (
        try {
            apply-media-projection ($work | path join "pub") ($work | path join "agg-empty")
            null
        } catch {|e| $e.msg}
    )

    ^rm -rf $work
    [
        (assert-not-null $err_msg "projection errors when opt dir has no required files")
        (assert-truthy ($err_msg | str contains "required primary optimized file missing")
            "error contains required primary optimized file missing")
        (assert-truthy (
            ($err_msg | str contains ".avif")
            or ($err_msg | str contains ".av1.webm")
        ) "error mentions a missing primary optimized file extension")
    ]
}

def main [] {
    test-log "=== integration/optimized-media-pipeline tests ==="
    let results = (
        (test-e2e-aggregate-then-project-success)
        | append (test-e2e-no-source-media-cell)
        | append (test-e2e-publish-fails-on-empty-opt-dir-with-media)
    ) | flatten
    run-suite "integration/optimized-media-pipeline" $SUITE_PATH $results
}
