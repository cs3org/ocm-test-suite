# Unit tests for aggregate-optimized-media helpers.
# Run: nu scripts/tests/artifacts/aggregate-optimized-media.nu
# Returns exit 0 on all pass, exit 1 with details on any failure.

const SUITE_PATH = path self

use ../../lib/artifacts/aggregate-optimized-media.nu [
    validate-optimized-path
    check-kind-ext-match
    read-cell-optimized-manifest
    aggregate-optimized-media-cells
    write-optimized-summary
]
use ../../lib/tests/assert.nu *
use ../../lib/tests/runner.nu [run-suite]

# --- validate-optimized-path ---

def test-validate-path-empty [] {
    test-log "\n[test-validate-path-empty]"
    let failed = (try { validate-optimized-path ""; false } catch { true })
    [(assert-truthy $failed "empty path is rejected")]
}

def test-validate-path-absolute [] {
    test-log "\n[test-validate-path-absolute]"
    let failed = (try { validate-optimized-path "/etc/passwd"; false } catch { true })
    [(assert-truthy $failed "absolute path is rejected")]
}

def test-validate-path-traversal [] {
    test-log "\n[test-validate-path-traversal]"
    let failed1 = (try { validate-optimized-path "../evil"; false } catch { true })
    let failed2 = (try { validate-optimized-path "a/../../b"; false } catch { true })
    [
        (assert-truthy $failed1 "../evil is rejected")
        (assert-truthy $failed2 "a/../../b is rejected")
    ]
}

def test-validate-path-ok [] {
    test-log "\n[test-validate-path-ok]"
    let ok1 = (try { validate-optimized-path "artifacts/f/p/e/cypress/screenshots/foo.avif"; true } catch { false })
    let ok2 = (try { validate-optimized-path "artifacts/f/p/e/cypress/videos/bar.av1.webm"; true } catch { false })
    let ok3 = (try { validate-optimized-path "foo.webp"; true } catch { false })
    [
        (assert-truthy $ok1 "full run-relative artifact path passes")
        (assert-truthy $ok2 "full run-relative video path passes")
        (assert-truthy $ok3 "flat path passes")
    ]
}

# --- check-kind-ext-match ---

def test-kind-ext-screenshot-webm-rejected [] {
    test-log "\n[test-kind-ext-screenshot-webm-rejected]"
    let msg = (check-kind-ext-match "screenshot" "foo.webm")
    [(assert-truthy (not ($msg | is-empty)) "screenshot + .webm produces error message")]
}

def test-kind-ext-video-avif-rejected [] {
    test-log "\n[test-kind-ext-video-avif-rejected]"
    let msg = (check-kind-ext-match "video" "bar.avif")
    [(assert-truthy (not ($msg | is-empty)) "video + .avif produces error message")]
}

def test-kind-ext-video-webp-rejected [] {
    test-log "\n[test-kind-ext-video-webp-rejected]"
    let msg = (check-kind-ext-match "video" "bar.webp")
    [(assert-truthy (not ($msg | is-empty)) "video + .webp produces error message")]
}

def test-kind-ext-screenshot-avif-ok [] {
    test-log "\n[test-kind-ext-screenshot-avif-ok]"
    let msg = (check-kind-ext-match "screenshot" "foo.avif")
    [(assert-truthy ($msg | is-empty) "screenshot + .avif is consistent")]
}

def test-kind-ext-screenshot-webp-ok [] {
    test-log "\n[test-kind-ext-screenshot-webp-ok]"
    let msg = (check-kind-ext-match "screenshot" "foo.webp")
    [(assert-truthy ($msg | is-empty) "screenshot + .webp is consistent")]
}

def test-kind-ext-video-webm-ok [] {
    test-log "\n[test-kind-ext-video-webm-ok]"
    let msg1 = (check-kind-ext-match "video" "bar.av1.webm")
    let msg2 = (check-kind-ext-match "video" "bar.vp9.webm")
    [
        (assert-truthy ($msg1 | is-empty) "video + .av1.webm is consistent")
        (assert-truthy ($msg2 | is-empty) "video + .vp9.webm is consistent")
    ]
}

def test-kind-ext-unknown-kind-ok [] {
    test-log "\n[test-kind-ext-unknown-kind-ok]"
    # Unknown kinds are not checked locally; no error emitted.
    let msg = (check-kind-ext-match "audio" "track.mp3")
    [(assert-truthy ($msg | is-empty) "unknown kind produces no error")]
}

# --- read-cell-optimized-manifest ---

def test-read-manifest-missing [] {
    test-log "\n[test-read-manifest-missing]"
    let id = (random uuid)
    let tmp = $"/tmp/ocmts-test-aggopt-missing-($id)"
    mkdir $tmp
    let result = (read-cell-optimized-manifest $tmp)
    try { rm -rf $tmp } catch {}
    [(assert-null $result "missing manifest returns null")]
}

def test-read-manifest-present [] {
    test-log "\n[test-read-manifest-present]"
    let id = (random uuid)
    let tmp = $"/tmp/ocmts-test-aggopt-manifest-($id)"
    mkdir ($tmp | path join "meta")
    {
        schema_version: 1,
        generated_at: "2026-01-01T00:00:00Z",
        status: "no-source-media",
        optimizer_image: "test-image:latest",
        items: [],
    } | to json | save ($tmp | path join "meta/optimized-media-cell.v1.json")
    let result = (read-cell-optimized-manifest $tmp)
    try { rm -rf $tmp } catch {}
    [
        (assert-not-null $result "manifest is returned when file exists")
        (assert-eq ($result.status? | default "") "no-source-media" "manifest status is read")
        (assert-eq ($result.schema_version? | default 0) 1 "manifest schema_version is read")
    ]
}

# --- aggregate-optimized-media-cells ---

def test-aggregate-empty-input [] {
    test-log "\n[test-aggregate-empty-input]"
    let id = (random uuid)
    let out_tmp = $"/tmp/ocmts-test-aggopt-empty-out-($id)"
    let failed = (try {
        aggregate-optimized-media-cells [] $out_tmp --no-archive
        false
    } catch { true })
    try { rm -rf $out_tmp } catch {}
    [(assert-truthy $failed "empty artifact_dirs raises an error")]
}

def test-aggregate-no-source-media-cells [] {
    test-log "\n[test-aggregate-no-source-media-cells]"
    let id = (random uuid)
    let cell1 = $"/tmp/ocmts-test-aggopt-nosrc-c1-($id)"
    let cell2 = $"/tmp/ocmts-test-aggopt-nosrc-c2-($id)"
    let out_tmp = $"/tmp/ocmts-test-aggopt-nosrc-out-($id)"
    mkdir ($cell1 | path join "meta")
    mkdir ($cell2 | path join "meta")
    {schema_version: 1, generated_at: "2026-01-01T00:00:00Z", status: "no-source-media",
        optimizer_image: "img:latest", items: []}
    | to json | save ($cell1 | path join "meta/optimized-media-cell.v1.json")
    {schema_version: 1, generated_at: "2026-01-01T00:00:00Z", status: "no-source-media",
        optimizer_image: "img:latest", items: []}
    | to json | save ($cell2 | path join "meta/optimized-media-cell.v1.json")

    let result = (aggregate-optimized-media-cells [$cell1 $cell2] $out_tmp --no-archive)
    let summary_exists = (($out_tmp | path join "meta/optimized-media-summary.v1.json") | path exists)

    try { rm -rf $cell1 } catch {}
    try { rm -rf $cell2 } catch {}
    try { rm -rf $out_tmp } catch {}
    [
        (assert-eq $result.cells_found 2 "two cells found")
        (assert-eq $result.cells_without_media 2 "both cells without media")
        (assert-eq $result.cells_with_media 0 "no cells with media")
        (assert-eq $result.cells_missing_manifest 0 "no missing manifests")
        (assert-eq $result.optimized_item_count 0 "no optimized items")
        (assert-eq $result.failed_item_count 0 "no failed items")
        (assert-null $result.archive_path "archive_path is null with --no-archive")
        (assert-truthy $summary_exists "summary manifest is written")
    ]
}

def test-aggregate-summary-shape [] {
    test-log "\n[test-aggregate-summary-shape]"
    let id = (random uuid)
    let cell1 = $"/tmp/ocmts-test-aggopt-shape-c1-($id)"
    let out_tmp = $"/tmp/ocmts-test-aggopt-shape-out-($id)"
    mkdir ($cell1 | path join "meta")
    {schema_version: 1, generated_at: "2026-01-01T00:00:00Z", status: "no-source-media",
        optimizer_image: "myimg:v1", items: []}
    | to json | save ($cell1 | path join "meta/optimized-media-cell.v1.json")

    aggregate-optimized-media-cells [$cell1] $out_tmp --no-archive
    let summary = (open ($out_tmp | path join "meta/optimized-media-summary.v1.json"))

    try { rm -rf $cell1 } catch {}
    try { rm -rf $out_tmp } catch {}
    [
        (assert-eq ($summary.schema_version? | default 0) 1 "schema_version is 1")
        (assert-truthy (not ($summary.generated_at? | default "" | is-empty)) "generated_at is set")
        (assert-truthy ("cells_found" in ($summary | columns)) "has cells_found")
        (assert-truthy ("cells_with_media" in ($summary | columns)) "has cells_with_media")
        (assert-truthy ("cells_without_media" in ($summary | columns)) "has cells_without_media")
        (assert-truthy ("cells_missing_manifest" in ($summary | columns)) "has cells_missing_manifest")
        (assert-truthy ("item_counts" in ($summary | columns)) "has item_counts")
        (assert-truthy ("cell_counts_by_status" in ($summary | columns)) "has cell_counts_by_status")
        (assert-truthy ("cell_summaries" in ($summary | columns)) "has cell_summaries")
        (assert-truthy ("optimizer_images" in ($summary | columns)) "has optimizer_images")
        (assert-eq ($summary.cells_found) 1 "cells_found is 1")
        (assert-list-contains $summary.optimizer_images "myimg:v1" "optimizer image recorded")
    ]
}

def test-aggregate-cell-counts-with-media [] {
    test-log "\n[test-aggregate-cell-counts-with-media]"
    let id = (random uuid)
    let cell_a = $"/tmp/ocmts-test-aggopt-counts-a-($id)"
    let cell_b = $"/tmp/ocmts-test-aggopt-counts-b-($id)"
    let out_tmp = $"/tmp/ocmts-test-aggopt-counts-out-($id)"

    # cell_a: with optimized media - paths use the truthful artifacts/... layout.
    mkdir ($cell_a | path join "meta")
    {
        schema_version: 1, generated_at: "2026-01-01T00:00:00Z", status: "optimized",
        optimizer_image: "img:1", items: [
            {source_path: "artifacts/f/p/e/cypress/screenshots/a.png",
                optimized_path: "artifacts/f/p/e/cypress/screenshots/a.avif",
                kind: "screenshot", status: "optimized", role: "primary", format: "avif", mime: "image/avif"},
            {source_path: "artifacts/f/p/e/cypress/screenshots/a.png",
                optimized_path: "artifacts/f/p/e/cypress/screenshots/a.webp",
                kind: "screenshot", status: "optimized", role: "fallback", format: "webp", mime: "image/webp"},
        ],
    } | to json | save ($cell_a | path join "meta/optimized-media-cell.v1.json")

    # cell_b: no source media
    mkdir ($cell_b | path join "meta")
    {schema_version: 1, generated_at: "2026-01-01T00:00:00Z", status: "no-source-media",
        optimizer_image: "img:1", items: []}
    | to json | save ($cell_b | path join "meta/optimized-media-cell.v1.json")

    let result = (aggregate-optimized-media-cells [$cell_a $cell_b] $out_tmp --no-archive)

    try { rm -rf $cell_a } catch {}
    try { rm -rf $cell_b } catch {}
    try { rm -rf $out_tmp } catch {}
    [
        (assert-eq $result.cells_found 2 "two cells found")
        (assert-eq $result.cells_with_media 1 "one cell with media")
        (assert-eq $result.cells_without_media 1 "one cell without media")
        (assert-eq $result.optimized_item_count 2 "two optimized items")
        (assert-eq $result.failed_item_count 0 "no failed items")
    ]
}

def test-aggregate-missing-manifest-cell [] {
    test-log "\n[test-aggregate-missing-manifest-cell]"
    let id = (random uuid)
    let cell_no_manifest = $"/tmp/ocmts-test-aggopt-nomfst-c-($id)"
    let out_tmp = $"/tmp/ocmts-test-aggopt-nomfst-out-($id)"
    mkdir $cell_no_manifest  # dir exists but no manifest file

    let result = (aggregate-optimized-media-cells [$cell_no_manifest] $out_tmp --no-archive)

    try { rm -rf $cell_no_manifest } catch {}
    try { rm -rf $out_tmp } catch {}
    [
        (assert-eq $result.cells_found 1 "one cell found")
        (assert-eq $result.cells_missing_manifest 1 "one missing manifest")
        (assert-eq $result.cells_with_media 0 "no cells with media")
        (assert-eq $result.cells_without_media 0 "no cells without media")
    ]
}

def test-aggregate-artifacts-tree-layout [] {
    test-log "\n[test-aggregate-artifacts-tree-layout]"
    let id = (random uuid)
    let cell_dir = $"/tmp/ocmts-test-aggopt-tree-c-($id)"
    let out_tmp = $"/tmp/ocmts-test-aggopt-tree-out-($id)"
    mkdir ($cell_dir | path join "meta")

    # The per-cell optimized dir has media at the truthful run-relative path.
    let media_rel_pri = "artifacts/f/p/e/cypress/screenshots/shot.avif"
    let media_rel_fal = "artifacts/f/p/e/cypress/screenshots/shot.webp"
    mkdir ($cell_dir | path join "artifacts/f/p/e/cypress/screenshots")
    "fake avif content" | save ($cell_dir | path join $media_rel_pri)
    "fake webp content" | save ($cell_dir | path join $media_rel_fal)

    {
        schema_version: 1, generated_at: "2026-01-01T00:00:00Z", status: "optimized",
        optimizer_image: "img:1", items: [
            {source_path: "artifacts/f/p/e/cypress/screenshots/shot.png",
                optimized_path: $media_rel_pri,
                kind: "screenshot", status: "optimized", role: "primary",
                format: "avif", mime: "image/avif"},
            {source_path: "artifacts/f/p/e/cypress/screenshots/shot.png",
                optimized_path: $media_rel_fal,
                kind: "screenshot", status: "optimized", role: "fallback",
                format: "webp", mime: "image/webp"},
        ],
    } | to json | save ($cell_dir | path join "meta/optimized-media-cell.v1.json")

    aggregate-optimized-media-cells [$cell_dir] $out_tmp --no-archive

    # The aggregate places the file directly at out_dir/<optimized_path>.
    let media_dest_pri = ($out_tmp | path join $media_rel_pri)
    let media_dest_fal = ($out_tmp | path join $media_rel_fal)
    let summary_dest = ($out_tmp | path join "meta/optimized-media-summary.v1.json")

    let pri_ok = ($media_dest_pri | path exists)
    let fal_ok = ($media_dest_fal | path exists)
    let summary_ok = ($summary_dest | path exists)

    try { rm -rf $cell_dir } catch {}
    try { rm -rf $out_tmp } catch {}
    [
        (assert-truthy $pri_ok "primary media file placed at out_dir/artifacts/... (truthful run-relative path)")
        (assert-truthy $fal_ok "fallback media file placed at out_dir/artifacts/...")
        (assert-truthy $summary_ok "summary manifest written")
    ]
}

def test-aggregate-duplicate-path-rejected [] {
    test-log "\n[test-aggregate-duplicate-path-rejected]"
    let id = (random uuid)
    let cell1 = $"/tmp/ocmts-test-aggopt-dup-c1-($id)"
    let cell2 = $"/tmp/ocmts-test-aggopt-dup-c2-($id)"
    let out_tmp = $"/tmp/ocmts-test-aggopt-dup-out-($id)"
    mkdir ($cell1 | path join "meta")
    mkdir ($cell2 | path join "meta")

    # Both cells claim the same run-relative optimized_path; aggregate must reject this.
    # Use a complete primary+fallback set so only the dup-path check fires, not the
    # variant completeness check.
    let shared_pri = {
        source_path: "artifacts/f/p/e/cypress/screenshots/a.png",
        optimized_path: "artifacts/f/p/e/cypress/screenshots/a.avif",
        kind: "screenshot", status: "optimized", role: "primary",
        format: "avif", mime: "image/avif",
    }
    let shared_fal = {
        source_path: "artifacts/f/p/e/cypress/screenshots/a.png",
        optimized_path: "artifacts/f/p/e/cypress/screenshots/a.webp",
        kind: "screenshot", status: "optimized", role: "fallback",
        format: "webp", mime: "image/webp",
    }
    {schema_version: 1, generated_at: "2026-01-01T00:00:00Z", status: "optimized",
        optimizer_image: "img:1", items: [$shared_pri $shared_fal]}
    | to json | save ($cell1 | path join "meta/optimized-media-cell.v1.json")
    {schema_version: 1, generated_at: "2026-01-01T00:00:00Z", status: "optimized",
        optimizer_image: "img:1", items: [$shared_pri $shared_fal]}
    | to json | save ($cell2 | path join "meta/optimized-media-cell.v1.json")

    let failed = (try {
        aggregate-optimized-media-cells [$cell1 $cell2] $out_tmp --no-archive
        false
    } catch { true })

    try { rm -rf $cell1 } catch {}
    try { rm -rf $cell2 } catch {}
    try { rm -rf $out_tmp } catch {}
    [(assert-truthy $failed "duplicate optimized_path across cells is rejected")]
}

def test-aggregate-unsafe-path-in-manifest-rejected [] {
    test-log "\n[test-aggregate-unsafe-path-in-manifest-rejected]"
    let id = (random uuid)
    let cell1 = $"/tmp/ocmts-test-aggopt-unsafe-c1-($id)"
    let out_tmp = $"/tmp/ocmts-test-aggopt-unsafe-out-($id)"
    mkdir ($cell1 | path join "meta")

    # Unsafe path in primary - no need for a fallback since path validation fires first.
    {schema_version: 1, generated_at: "2026-01-01T00:00:00Z", status: "optimized",
        optimizer_image: "img:1", items: [
            {source_path: "a.png", optimized_path: "../../../etc/passwd",
                kind: "screenshot", status: "optimized", role: "primary",
                format: "avif", mime: "image/avif"},
            {source_path: "a.png", optimized_path: "a.webp",
                kind: "screenshot", status: "optimized", role: "fallback",
                format: "webp", mime: "image/webp"},
        ]}
    | to json | save ($cell1 | path join "meta/optimized-media-cell.v1.json")

    let failed = (try {
        aggregate-optimized-media-cells [$cell1] $out_tmp --no-archive
        false
    } catch { true })

    try { rm -rf $cell1 } catch {}
    try { rm -rf $out_tmp } catch {}
    [(assert-truthy $failed "path traversal in manifest optimized_path is rejected")]
}

def test-aggregate-kind-ext-mismatch-rejected [] {
    test-log "\n[test-aggregate-kind-ext-mismatch-rejected]"
    let id = (random uuid)
    let cell1 = $"/tmp/ocmts-test-aggopt-mismatch-c1-($id)"
    let out_tmp = $"/tmp/ocmts-test-aggopt-mismatch-out-($id)"
    mkdir ($cell1 | path join "meta")

    # screenshot kind but .webm extension - mismatch in primary
    {schema_version: 1, generated_at: "2026-01-01T00:00:00Z", status: "optimized",
        optimizer_image: "img:1", items: [
            {source_path: "a.png", optimized_path: "a.webm",
                kind: "screenshot", status: "optimized", role: "primary",
                format: "webm", mime: "video/webm"},
            {source_path: "a.png", optimized_path: "a2.webm",
                kind: "screenshot", status: "optimized", role: "fallback",
                format: "webm", mime: "video/webm"},
        ]}
    | to json | save ($cell1 | path join "meta/optimized-media-cell.v1.json")

    let failed = (try {
        aggregate-optimized-media-cells [$cell1] $out_tmp --no-archive
        false
    } catch { true })

    try { rm -rf $cell1 } catch {}
    try { rm -rf $out_tmp } catch {}
    [(assert-truthy $failed "screenshot kind with .webm optimized_path is rejected")]
}

def test-aggregate-deterministic-order [] {
    test-log "\n[test-aggregate-deterministic-order]"
    let id = (random uuid)
    # Create two cells with predictable basename ordering.
    let cell_b = $"/tmp/ocmts-test-aggopt-order-b-($id)"
    let cell_a = $"/tmp/ocmts-test-aggopt-order-a-($id)"
    let out_tmp = $"/tmp/ocmts-test-aggopt-order-out-($id)"
    mkdir ($cell_a | path join "meta")
    mkdir ($cell_b | path join "meta")
    {schema_version: 1, generated_at: "2026-01-01T00:00:00Z", status: "no-source-media",
        optimizer_image: "img:1", items: []}
    | to json | save ($cell_a | path join "meta/optimized-media-cell.v1.json")
    {schema_version: 1, generated_at: "2026-01-01T00:00:00Z", status: "no-source-media",
        optimizer_image: "img:1", items: []}
    | to json | save ($cell_b | path join "meta/optimized-media-cell.v1.json")

    # Pass in reverse order; result should still be deterministic (sorted).
    let result = (aggregate-optimized-media-cells [$cell_b $cell_a] $out_tmp --no-archive)
    let summary = (open ($out_tmp | path join "meta/optimized-media-summary.v1.json"))
    let keys = ($summary.cell_summaries | each {|s| $s.cell_key})

    try { rm -rf $cell_a } catch {}
    try { rm -rf $cell_b } catch {}
    try { rm -rf $out_tmp } catch {}
    [
        (assert-eq $result.cells_found 2 "two cells aggregated")
        # Sorted: a-... < b-..., so first key contains "order-a"
        (assert-truthy (($keys | first) | str contains "order-a") "cell summaries sorted by dir basename")
    ]
}

# --- Task C: variant completeness validation ---

def test-aggregate-missing-fallback-rejected [] {
    test-log "\n[test-aggregate-missing-fallback-rejected]"
    let id = (random uuid)
    let cell1 = $"/tmp/ocmts-test-aggopt-nofb-c1-($id)"
    let out_tmp = $"/tmp/ocmts-test-aggopt-nofb-out-($id)"
    mkdir ($cell1 | path join "meta")
    # Only primary - no fallback for this source_path.
    {schema_version: 1, generated_at: "2026-01-01T00:00:00Z", status: "optimized",
        optimizer_image: "img:1", items: [
            {source_path: "artifacts/f/p/e/cypress/screenshots/a.png",
                optimized_path: "artifacts/f/p/e/cypress/screenshots/a.avif",
                kind: "screenshot", status: "optimized", role: "primary", format: "avif", mime: "image/avif"},
        ]}
    | to json | save ($cell1 | path join "meta/optimized-media-cell.v1.json")

    let result = (try {
        aggregate-optimized-media-cells [$cell1] $out_tmp --no-archive
        "ok"
    } catch {|e| $e.msg})

    try { rm -rf $cell1 } catch {}
    try { rm -rf $out_tmp } catch {}
    [
        (assert-truthy ($result | str contains "fallback") "error mentions missing fallback role")
        (assert-truthy ($result | str contains "a.png") "error mentions the source path")
    ]
}

def test-aggregate-duplicate-primary-rejected [] {
    test-log "\n[test-aggregate-duplicate-primary-rejected]"
    let id = (random uuid)
    let cell1 = $"/tmp/ocmts-test-aggopt-dupri-c1-($id)"
    let out_tmp = $"/tmp/ocmts-test-aggopt-dupri-out-($id)"
    mkdir ($cell1 | path join "meta")
    # Two primary items for the same source path.
    {schema_version: 1, generated_at: "2026-01-01T00:00:00Z", status: "optimized",
        optimizer_image: "img:1", items: [
            {source_path: "artifacts/f/p/e/cypress/screenshots/a.png",
                optimized_path: "artifacts/f/p/e/cypress/screenshots/a.avif",
                kind: "screenshot", status: "optimized", role: "primary", format: "avif", mime: "image/avif"},
            {source_path: "artifacts/f/p/e/cypress/screenshots/a.png",
                optimized_path: "artifacts/f/p/e/cypress/screenshots/a2.avif",
                kind: "screenshot", status: "optimized", role: "primary", format: "avif", mime: "image/avif"},
            {source_path: "artifacts/f/p/e/cypress/screenshots/a.png",
                optimized_path: "artifacts/f/p/e/cypress/screenshots/a.webp",
                kind: "screenshot", status: "optimized", role: "fallback", format: "webp", mime: "image/webp"},
        ]}
    | to json | save ($cell1 | path join "meta/optimized-media-cell.v1.json")

    let result = (try {
        aggregate-optimized-media-cells [$cell1] $out_tmp --no-archive
        "ok"
    } catch {|e| $e.msg})

    try { rm -rf $cell1 } catch {}
    try { rm -rf $out_tmp } catch {}
    [
        (assert-truthy ($result | str contains "primary") "error mentions duplicate primary role")
    ]
}

# --- Task D: renamed summary structure ---

def test-aggregate-summary-no-source-media-in-item-counts [] {
    test-log "\n[test-aggregate-summary-no-source-media-in-item-counts]"
    let id = (random uuid)
    let cell1 = $"/tmp/ocmts-test-aggopt-rename-c1-($id)"
    let out_tmp = $"/tmp/ocmts-test-aggopt-rename-out-($id)"
    mkdir ($cell1 | path join "meta")
    {schema_version: 1, generated_at: "2026-01-01T00:00:00Z", status: "no-source-media",
        optimizer_image: "img:1", items: []}
    | to json | save ($cell1 | path join "meta/optimized-media-cell.v1.json")

    aggregate-optimized-media-cells [$cell1] $out_tmp --no-archive
    let summary = (open ($out_tmp | path join "meta/optimized-media-summary.v1.json"))
    let ic_cols = ($summary.item_counts | columns)
    let cbs_cols = ($summary.cell_counts_by_status | columns)

    try { rm -rf $cell1 } catch {}
    try { rm -rf $out_tmp } catch {}
    [
        (assert-truthy (not ("no_source_media" in $ic_cols)) "item_counts has no no_source_media key")
        (assert-truthy ("optimized" in $ic_cols) "item_counts still has optimized key")
        (assert-truthy ("failed" in $ic_cols) "item_counts still has failed key")
        (assert-truthy ("no_source_media" in $cbs_cols) "cell_counts_by_status has no_source_media key")
        (assert-truthy ("missing_manifest" in $cbs_cols) "cell_counts_by_status has missing_manifest key")
        (assert-eq $summary.cell_counts_by_status.no_source_media 1 "cell_counts_by_status.no_source_media = 1")
    ]
}

def main [] {
    let results = (
        (test-validate-path-empty)
        | append (test-validate-path-absolute)
        | append (test-validate-path-traversal)
        | append (test-validate-path-ok)
        | append (test-kind-ext-screenshot-webm-rejected)
        | append (test-kind-ext-video-avif-rejected)
        | append (test-kind-ext-video-webp-rejected)
        | append (test-kind-ext-screenshot-avif-ok)
        | append (test-kind-ext-screenshot-webp-ok)
        | append (test-kind-ext-video-webm-ok)
        | append (test-kind-ext-unknown-kind-ok)
        | append (test-read-manifest-missing)
        | append (test-read-manifest-present)
        | append (test-aggregate-empty-input)
        | append (test-aggregate-no-source-media-cells)
        | append (test-aggregate-summary-shape)
        | append (test-aggregate-cell-counts-with-media)
        | append (test-aggregate-missing-manifest-cell)
        | append (test-aggregate-artifacts-tree-layout)
        | append (test-aggregate-duplicate-path-rejected)
        | append (test-aggregate-unsafe-path-in-manifest-rejected)
        | append (test-aggregate-kind-ext-mismatch-rejected)
        | append (test-aggregate-deterministic-order)
        | append (test-aggregate-missing-fallback-rejected)
        | append (test-aggregate-duplicate-primary-rejected)
        | append (test-aggregate-summary-no-source-media-in-item-counts)
    )
    run-suite "artifacts/aggregate-optimized-media" $SUITE_PATH $results
}
