# Tests for scripts/lib/site/project-media.nu
# Covers: projection behavior, failure semantics, path safety.
# Run: nu scripts/tests/site/project-media.nu

const SUITE_PATH = path self

use ../../lib/site/project-media.nu [
    check-path-safe
    check-kind-path-match
    derive-media-variants
    resolve-run-prefix
    project-one-evidence-item
    manifest-has-media-rows
    assert-under-pub-dir
    assert-projected-media-row-derived-only
    apply-media-projection
    require-optimized-media-when-needed
]
use ../../lib/tests/assert.nu *
use ../../lib/tests/runner.nu [run-suite]

# --- check-path-safe ---

def test-check-path-safe-ok [] {
    test-log "\n[test-check-path-safe-ok]"
    [
        (assert-eq (check-path-safe "cypress/screenshots/foo.png") ""
            "normal relative path is safe")
        (assert-eq (check-path-safe "artifacts/login/nc-v34/exec1/cypress/videos/run.mp4") ""
            "deep relative path is safe")
    ]
}

def test-check-path-safe-empty [] {
    test-log "\n[test-check-path-safe-empty]"
    [
        (assert-truthy (not ((check-path-safe "") | is-empty))
            "empty path is rejected")
    ]
}

def test-check-path-safe-absolute [] {
    test-log "\n[test-check-path-safe-absolute]"
    [
        (assert-truthy (not ((check-path-safe "/etc/passwd") | is-empty))
            "absolute path is rejected")
        (assert-truthy (not ((check-path-safe "/tmp/foo.avif") | is-empty))
            "absolute tmp path is rejected")
    ]
}

def test-check-path-safe-traversal [] {
    test-log "\n[test-check-path-safe-traversal]"
    [
        (assert-truthy (not ((check-path-safe "../secret.json") | is-empty))
            "../ traversal is rejected")
        (assert-truthy (not ((check-path-safe "foo/../../etc") | is-empty))
            "embedded .. is rejected")
    ]
}

# --- check-kind-path-match ---

def test-check-kind-path-match-ok [] {
    test-log "\n[test-check-kind-path-match-ok]"
    [
        (assert-eq (check-kind-path-match "screenshot" "cypress/screenshots/foo.png") ""
            "screenshot + .png is valid")
        (assert-eq (check-kind-path-match "video" "cypress/videos/run.mp4") ""
            "video + .mp4 is valid")
    ]
}

def test-check-kind-path-match-bad [] {
    test-log "\n[test-check-kind-path-match-bad]"
    [
        (assert-truthy (not ((check-kind-path-match "screenshot" "foo.mp4") | is-empty))
            "screenshot + .mp4 is rejected")
        (assert-truthy (not ((check-kind-path-match "video" "foo.png") | is-empty))
            "video + .png is rejected")
        (assert-truthy (not ((check-kind-path-match "screenshot" "foo.avif") | is-empty))
            "screenshot + .avif source is rejected")
    ]
}

# --- derive-media-variants ---

def test-derive-screenshot-variants [] {
    test-log "\n[test-derive-screenshot-variants]"
    let result = (derive-media-variants
        "cypress/screenshots/index.cy.ts/foo--001--bar.png"
        "screenshot")
    [
        (assert-eq $result.primary_rel
            "cypress/screenshots/index.cy.ts/foo--001--bar.avif"
            "screenshot primary is avif")
        (assert-eq $result.fallback_rel
            "cypress/screenshots/index.cy.ts/foo--001--bar.webp"
            "screenshot fallback is webp")
        (assert-eq $result.primary_fmt "avif" "primary format is avif")
        (assert-eq $result.primary_mime "image/avif" "primary mime is image/avif")
        (assert-eq $result.fallback_fmt "webp" "fallback format is webp")
        (assert-eq $result.fallback_mime "image/webp" "fallback mime is image/webp")
    ]
}

def test-derive-video-variants [] {
    test-log "\n[test-derive-video-variants]"
    let result = (derive-media-variants "cypress/videos/run.mp4" "video")
    [
        (assert-eq $result.primary_rel "cypress/videos/run.av1.webm"
            "video primary is av1.webm")
        (assert-eq $result.fallback_rel "cypress/videos/run.vp9.webm"
            "video fallback is vp9.webm")
        (assert-eq $result.primary_fmt "av1-webm" "primary format is av1-webm")
        (assert-eq $result.primary_mime "video/webm" "primary mime is video/webm")
        (assert-eq $result.primary_codecs "av01" "primary codecs is av01")
        (assert-eq $result.fallback_fmt "vp9-webm" "fallback format is vp9-webm")
        (assert-eq $result.fallback_mime "video/webm" "fallback mime is video/webm")
        (assert-eq $result.fallback_codecs "vp9" "fallback codecs is vp9")
    ]
}

def test-derive-unknown-kind-returns-null [] {
    test-log "\n[test-derive-unknown-kind-returns-null]"
    let result = (derive-media-variants "cypress/screenshots/foo.png" "metadata")
    [
        (assert-null $result "unknown kind returns null")
    ]
}

def test-derive-logical-name-is-filename [] {
    test-log "\n[test-derive-logical-name-is-filename]"
    let v = (derive-media-variants "cypress/screenshots/sub/long--name.png" "screenshot")
    [
        (assert-eq ($v.primary_rel | path basename) "long--name.avif"
            "basename of primary_rel is the derived logical_name")
    ]
}

# --- resolve-run-prefix ---

def make-manifest-fixture [flow_id: string, pair: string, exec_id: string] {
    let cell_id = $"($flow_id)__($pair)"
    let run_id = $"run-($exec_id)"
    let result_id = $"res-($exec_id)"
    {
        runs: {
            ($run_id): {
                id: $run_id
                cell_id: $cell_id
                execution_id: $exec_id
            }
        }
        cells: {
            ($cell_id): {
                id: $cell_id
                flow_id: $flow_id
                pair: $pair
            }
        }
        results: {
            ($result_id): {
                id: $result_id
                run_id: $run_id
                cell_id: $cell_id
                evidence: []
            }
        }
    }
}

def test-resolve-run-prefix-ok [] {
    test-log "\n[test-resolve-run-prefix-ok]"
    let mf = (make-manifest-fixture "login" "nextcloud-v34" "20260510t125801-abc")
    let result = ($mf.results | transpose k v | first).v
    let prefix = (resolve-run-prefix $result $mf)
    [
        (assert-eq $prefix "artifacts/login/nextcloud-v34/20260510t125801-abc"
            "prefix is artifacts/<flow>/<pair>/<exec_id>")
    ]
}

def test-resolve-run-prefix-missing-components [] {
    test-log "\n[test-resolve-run-prefix-missing-components]"
    let mf = {runs: {}, cells: {}, results: {}}
    let result = {run_id: "r1", cell_id: "c1"}
    let prefix = (resolve-run-prefix $result $mf)
    [
        (assert-eq $prefix "" "missing run/cell returns empty prefix")
    ]
}

# --- project-one-evidence-item ---

def make-ev [kind: string, ev_path: string] {
    {
        kind: $kind
        scope: "cypress"
        logical_name: ($ev_path | path basename)
        path: $ev_path
        availability: "artifact"
        evidence_id: "test-ev"
    }
}

def test-project-non-media-passthrough [] {
    test-log "\n[test-project-non-media-passthrough]"
    let ev = {kind: "metadata", scope: "meta", path: "meta/result.json", logical_name: "result.json"}
    let out = (project-one-evidence-item $ev "artifacts/f/p/e" "/nonexistent")
    [
        (assert-eq $out.error "" "non-media item has no error")
        (assert-eq $out.copy_ops [] "non-media item has no copy ops")
        (assert-eq $out.remove_ops [] "non-media item has no remove ops")
        (assert-eq $out.item $ev "non-media item is unchanged")
    ]
}

def test-project-screenshot-success [] {
    test-log "\n[test-project-screenshot-success]"
    # Set up a temp opt_agg_dir with the required files.
    let tmp = (^mktemp -d | str trim)
    let run_prefix = "artifacts/login/nc-v34/exec1"
    let ss_dir = ($tmp | path join $run_prefix "cypress/screenshots/index.cy.ts")
    mkdir $ss_dir
    $"avif-content" | save ($ss_dir | path join "foo--001.avif")
    $"webp-content" | save ($ss_dir | path join "foo--001.webp")

    let ev = (make-ev "screenshot" "cypress/screenshots/index.cy.ts/foo--001.png")
    let out = (project-one-evidence-item $ev $run_prefix $tmp)

    ^rm -rf $tmp
    [
        (assert-eq $out.error "" "no error when both variants present")
        (assert-eq $out.item.path "cypress/screenshots/index.cy.ts/foo--001.avif"
            "path is rewritten to avif")
        (assert-eq $out.item.logical_name "foo--001.avif"
            "logical_name is derived avif filename")
        (assert-eq $out.item.source_path "cypress/screenshots/index.cy.ts/foo--001.png"
            "source_path preserves raw path")
        (assert-eq ($out.item.media_variants | length) 2
            "media_variants has two items")
        (assert-eq ($out.item.media_variants | first).role "primary"
            "first media_variant is primary")
        (assert-eq ($out.item.media_variants | first).format "avif"
            "primary variant format is avif")
        (assert-eq ($out.item.media_variants | last).role "fallback"
            "second media_variant is fallback")
        (assert-eq ($out.item.media_variants | last).format "webp"
            "fallback variant format is webp")
        (assert-eq ($out.copy_ops | length) 2 "two copy ops (primary + fallback)")
        (assert-eq ($out.remove_ops | length) 1 "one remove op (raw png)")
        (assert-eq ($out.remove_ops | first) ($run_prefix | path join "cypress/screenshots/index.cy.ts/foo--001.png")
            "remove op is run_prefix + ev_path")
    ]
}

def test-project-video-success [] {
    test-log "\n[test-project-video-success]"
    let tmp = (^mktemp -d | str trim)
    let run_prefix = "artifacts/login/nc-v34/exec2"
    let vid_dir = ($tmp | path join $run_prefix "cypress/videos")
    mkdir $vid_dir
    $"av1-content" | save ($vid_dir | path join "run.av1.webm")
    $"vp9-content" | save ($vid_dir | path join "run.vp9.webm")

    let ev = (make-ev "video" "cypress/videos/run.mp4")
    let out = (project-one-evidence-item $ev $run_prefix $tmp)

    ^rm -rf $tmp
    [
        (assert-eq $out.error "" "no error when both video variants present")
        (assert-eq $out.item.path "cypress/videos/run.av1.webm"
            "path is rewritten to av1.webm")
        (assert-eq $out.item.logical_name "run.av1.webm"
            "logical_name is derived av1 filename")
        (assert-eq $out.item.source_path "cypress/videos/run.mp4"
            "source_path preserves raw mp4 path")
        (assert-eq ($out.item.media_variants | first).format "av1-webm"
            "primary variant format is av1-webm")
        (assert-eq ($out.item.media_variants | first).mime "video/webm"
            "primary variant mime is video/webm")
        (assert-eq ($out.item.media_variants | first).codecs "av01"
            "primary variant codecs is av01")
        (assert-eq ($out.item.media_variants | last).format "vp9-webm"
            "fallback variant format is vp9-webm")
        (assert-eq ($out.item.media_variants | last).mime "video/webm"
            "fallback variant mime is video/webm")
        (assert-eq ($out.item.media_variants | last).codecs "vp9"
            "fallback variant codecs is vp9")
    ]
}

def test-project-fails-when-primary-missing [] {
    test-log "\n[test-project-fails-when-primary-missing]"
    let tmp = (^mktemp -d | str trim)
    let run_prefix = "artifacts/f/p/e"
    let ss_dir = ($tmp | path join $run_prefix "cypress/screenshots")
    mkdir $ss_dir
    # Only write the fallback, not the primary.
    $"webp" | save ($ss_dir | path join "foo.webp")

    let ev = (make-ev "screenshot" "cypress/screenshots/foo.png")
    let out = (project-one-evidence-item $ev $run_prefix $tmp)

    ^rm -rf $tmp
    [
        (assert-truthy (not ($out.error | is-empty))
            "error when primary avif missing")
        (assert-truthy ($out.error | str contains "primary")
            "error message mentions primary")
    ]
}

def test-project-fails-when-fallback-missing [] {
    test-log "\n[test-project-fails-when-fallback-missing]"
    let tmp = (^mktemp -d | str trim)
    let run_prefix = "artifacts/f/p/e"
    let ss_dir = ($tmp | path join $run_prefix "cypress/screenshots")
    mkdir $ss_dir
    # Only write the primary, not the fallback.
    $"avif" | save ($ss_dir | path join "foo.avif")

    let ev = (make-ev "screenshot" "cypress/screenshots/foo.png")
    let out = (project-one-evidence-item $ev $run_prefix $tmp)

    ^rm -rf $tmp
    [
        (assert-truthy (not ($out.error | is-empty))
            "error when fallback webp missing")
        (assert-truthy ($out.error | str contains "fallback")
            "error message mentions fallback")
    ]
}

def test-project-rejects-absolute-ev-path [] {
    test-log "\n[test-project-rejects-absolute-ev-path]"
    let ev = (make-ev "screenshot" "/etc/passwd")
    let out = (project-one-evidence-item $ev "artifacts/f/p/e" "/tmp")
    [
        (assert-truthy (not ($out.error | is-empty))
            "absolute ev_path is rejected")
    ]
}

def test-project-rejects-traversal-ev-path [] {
    test-log "\n[test-project-rejects-traversal-ev-path]"
    let ev = (make-ev "screenshot" "../../etc/shadow.png")
    let out = (project-one-evidence-item $ev "artifacts/f/p/e" "/tmp")
    [
        (assert-truthy (not ($out.error | is-empty))
            ".. traversal in ev_path is rejected")
    ]
}

def test-project-rejects-kind-mismatch [] {
    test-log "\n[test-project-rejects-kind-mismatch]"
    let ev = (make-ev "screenshot" "cypress/videos/run.mp4")
    let out = (project-one-evidence-item $ev "artifacts/f/p/e" "/tmp")
    [
        (assert-truthy (not ($out.error | is-empty))
            "screenshot kind with .mp4 path is rejected")
    ]
}

# --- apply-media-projection integration ---

def test-apply-media-projection-full [] {
    test-log "\n[test-apply-media-projection-full]"
    let tmp = (^mktemp -d | str trim)
    let pub_dir = ($tmp | path join "public")
    let opt_dir = ($tmp | path join "opt-agg")

    # Build a minimal manifest fixture.
    let flow_id = "login"
    let pair = "nc-v34"
    let exec_id = "exec-abc"
    let cell_id = $"($flow_id)__($pair)"
    let run_id = "run-abc"
    let result_id = "res-abc"
    let run_prefix = $"artifacts/($flow_id)/($pair)/($exec_id)"

    let manifest = {
        schema_version: 1
        generated_at: "2026-01-01T00:00:00Z"
        runs: {
            ($run_id): {
                id: $run_id
                cell_id: $cell_id
                execution_id: $exec_id
            }
        }
        cells: {
            ($cell_id): {id: $cell_id, flow_id: $flow_id, pair: $pair}
        }
        results: {
            ($result_id): {
                id: $result_id
                run_id: $run_id
                cell_id: $cell_id
                evidence: [
                    {
                        kind: "screenshot"
                        scope: "cypress"
                        logical_name: "foo.png"
                        path: "cypress/screenshots/foo.png"
                        availability: "artifact"
                        evidence_id: "ev-ss"
                    }
                    {
                        kind: "metadata"
                        scope: "meta"
                        logical_name: "result.json"
                        path: "meta/result.json"
                        availability: "artifact"
                        evidence_id: "ev-meta"
                    }
                ]
            }
        }
    }

    # Write public manifest.
    mkdir $pub_dir
    $manifest | to json --indent 2 | save ($pub_dir | path join "suite-manifest.v1.json")

    # Write raw screenshot in public artifacts tree.
    let pub_ss_dir = ($pub_dir | path join $run_prefix "cypress/screenshots")
    mkdir $pub_ss_dir
    $"raw-png" | save ($pub_ss_dir | path join "foo.png")

    # Write optimized variants in opt aggregate.
    let opt_ss_dir = ($opt_dir | path join $run_prefix "cypress/screenshots")
    mkdir $opt_ss_dir
    $"avif-bytes" | save ($opt_ss_dir | path join "foo.avif")
    $"webp-bytes" | save ($opt_ss_dir | path join "foo.webp")

    # Run projection.
    apply-media-projection $pub_dir $opt_dir

    # Read projected manifest.
    let projected = (open ($pub_dir | path join "suite-manifest.v1.json"))
    let result = ($projected.results | get $result_id)
    let ss_ev = ($result.evidence | where kind == "screenshot" | first)
    let meta_ev = ($result.evidence | where kind == "metadata" | first)

    let avif_pub = ($pub_dir | path join $run_prefix "cypress/screenshots/foo.avif")
    let webp_pub = ($pub_dir | path join $run_prefix "cypress/screenshots/foo.webp")
    let png_pub = ($pub_dir | path join $run_prefix "cypress/screenshots/foo.png")

    # Collect existence flags before cleanup.
    let avif_exists = ($avif_pub | path exists)
    let webp_exists = ($webp_pub | path exists)
    let png_gone = (not ($png_pub | path exists))

    ^rm -rf $tmp
    [
        (assert-eq $ss_ev.path "cypress/screenshots/foo.avif"
            "screenshot path rewritten to avif")
        (assert-eq $ss_ev.logical_name "foo.avif"
            "screenshot logical_name is avif filename")
        (assert-eq $ss_ev.source_path "cypress/screenshots/foo.png"
            "screenshot source_path preserved")
        (assert-eq ($ss_ev.media_variants | first).format "avif"
            "media_variants first item is avif primary")
        (assert-eq ($ss_ev.media_variants | last).format "webp"
            "media_variants second item is webp fallback")
        (assert-eq $meta_ev.path "meta/result.json"
            "non-media evidence path unchanged")
        (assert-truthy $avif_exists "avif file copied to public tree")
        (assert-truthy $webp_exists "webp file copied to public tree")
        (assert-truthy $png_gone "raw png removed from public tree")
    ]
}

def test-apply-media-projection-fails-missing-optimized [] {
    test-log "\n[test-apply-media-projection-fails-missing-optimized]"
    let tmp = (^mktemp -d | str trim)
    let pub_dir = ($tmp | path join "public")
    let opt_dir = ($tmp | path join "opt-agg")

    let flow_id = "login"
    let pair = "nc-v34"
    let exec_id = "exec-xyz"
    let cell_id = $"($flow_id)__($pair)"
    let run_id = "run-xyz"
    let result_id = "res-xyz"

    let manifest = {
        schema_version: 1
        generated_at: "2026-01-01T00:00:00Z"
        runs: {
            ($run_id): {id: $run_id, cell_id: $cell_id, execution_id: $exec_id}
        }
        cells: {
            ($cell_id): {id: $cell_id, flow_id: $flow_id, pair: $pair}
        }
        results: {
            ($result_id): {
                id: $result_id
                run_id: $run_id
                cell_id: $cell_id
                evidence: [
                    {kind: "screenshot", path: "cypress/screenshots/missing.png",
                     logical_name: "missing.png", availability: "artifact",
                     scope: "cypress", evidence_id: "ev-missing"}
                ]
            }
        }
    }

    mkdir $pub_dir
    $manifest | to json --indent 2 | save ($pub_dir | path join "suite-manifest.v1.json")
    mkdir $opt_dir  # empty - no optimized files

    let result = (try { apply-media-projection $pub_dir $opt_dir; "ok" } catch {|e| $e.msg})

    ^rm -rf $tmp
    [
        (assert-truthy ($result | str contains "missing")
            "fails with missing optimized error message")
    ]
}

def test-apply-media-projection-missing-manifest-fails [] {
    test-log "\n[test-apply-media-projection-missing-manifest-fails]"
    let tmp = (^mktemp -d | str trim)
    let pub_dir = ($tmp | path join "no-public")
    let opt_dir = ($tmp | path join "opt")
    mkdir $opt_dir

    let result = (try { apply-media-projection $pub_dir $opt_dir; "ok" } catch {|e| $e.msg})
    ^rm -rf $tmp
    [
        (assert-truthy ($result | str contains "manifest not found")
            "fails when manifest does not exist")
    ]
}

# --- manifest-has-media-rows ---

def test-manifest-has-media-rows-true [] {
    test-log "\n[test-manifest-has-media-rows-true]"
    let tmp = (^mktemp -d | str trim)
    let pub_dir = ($tmp | path join "public")
    mkdir $pub_dir
    let manifest = {
        schema_version: 1
        results: {
            r1: {
                evidence: [
                    {kind: "screenshot", path: "cypress/screenshots/foo.png"}
                    {kind: "metadata", path: "meta/result.json"}
                ]
            }
        }
    }
    $manifest | to json --indent 2 | save ($pub_dir | path join "suite-manifest.v1.json")
    let result = (manifest-has-media-rows $pub_dir)
    ^rm -rf $tmp
    [(assert-eq $result true "manifest with screenshot evidence returns true")]
}

def test-manifest-has-media-rows-false-no-media [] {
    test-log "\n[test-manifest-has-media-rows-false-no-media]"
    let tmp = (^mktemp -d | str trim)
    let pub_dir = ($tmp | path join "public")
    mkdir $pub_dir
    let manifest = {
        schema_version: 1
        results: {
            r1: {evidence: [{kind: "metadata", path: "meta/result.json"}]}
        }
    }
    $manifest | to json --indent 2 | save ($pub_dir | path join "suite-manifest.v1.json")
    let result = (manifest-has-media-rows $pub_dir)
    ^rm -rf $tmp
    [(assert-eq $result false "manifest with only metadata evidence returns false")]
}

def test-manifest-has-media-rows-false-no-manifest [] {
    test-log "\n[test-manifest-has-media-rows-false-no-manifest]"
    let tmp = (^mktemp -d | str trim)
    let result = (manifest-has-media-rows $tmp)
    ^rm -rf $tmp
    [(assert-eq $result false "missing manifest returns false")]
}

def test-manifest-has-media-rows-video [] {
    test-log "\n[test-manifest-has-media-rows-video]"
    let tmp = (^mktemp -d | str trim)
    let pub_dir = ($tmp | path join "public")
    mkdir $pub_dir
    let manifest = {
        schema_version: 1
        results: {
            r1: {evidence: [{kind: "video", path: "cypress/videos/run.mp4"}]}
        }
    }
    $manifest | to json --indent 2 | save ($pub_dir | path join "suite-manifest.v1.json")
    let result = (manifest-has-media-rows $pub_dir)
    ^rm -rf $tmp
    [(assert-eq $result true "manifest with video evidence returns true")]
}

# --- apply-media-projection: no opt dir guard ---

def test-apply-media-projection-missing-opt-dir-fails [] {
    test-log "\n[test-apply-media-projection-missing-opt-dir-fails]"
    let tmp = (^mktemp -d | str trim)
    let pub_dir = ($tmp | path join "public")
    mkdir $pub_dir
    # Write a minimal manifest so we get past the manifest check.
    {schema_version: 1, results: {}} | to json | save ($pub_dir | path join "suite-manifest.v1.json")

    let result = (try { apply-media-projection $pub_dir "/nonexistent/opt-dir"; "ok" } catch {|e| $e.msg})
    ^rm -rf $tmp
    [
        (assert-truthy ($result | str contains "optimized media dir not found")
            "fails when opt_agg_dir does not exist")
    ]
}

# --- Task E: assert-under-pub-dir containment check ---

def test-assert-under-pub-dir-ok [] {
    test-log "\n[test-assert-under-pub-dir-ok]"
    let tmp = (^mktemp -d | str trim)
    let pub_dir = ($tmp | path join "public")
    mkdir $pub_dir
    let dst = ($pub_dir | path join "artifacts/f/p/e/foo.avif")
    let ok = (try { assert-under-pub-dir $pub_dir $dst; true } catch { false })
    ^rm -rf $tmp
    [(assert-truthy $ok "path inside pub_dir passes containment check")]
}

def test-assert-under-pub-dir-escapes-rejected [] {
    test-log "\n[test-assert-under-pub-dir-escapes-rejected]"
    let tmp = (^mktemp -d | str trim)
    let pub_dir = ($tmp | path join "public")
    mkdir $pub_dir
    # Path that escapes pub_dir.
    let dst = ($tmp | path join "outside.avif")
    let failed = (try { assert-under-pub-dir $pub_dir $dst; false } catch { true })
    ^rm -rf $tmp
    [(assert-truthy $failed "path escaping pub_dir is rejected")]
}

# --- Task F: orphan optimized file rejection ---

def test-apply-media-projection-orphan-rejected [] {
    test-log "\n[test-apply-media-projection-orphan-rejected]"
    let tmp = (^mktemp -d | str trim)
    let pub_dir = ($tmp | path join "public")
    let opt_dir = ($tmp | path join "opt-agg")

    let flow_id = "login"
    let pair = "nc-v34"
    let exec_id = "exec-orphan"
    let cell_id = $"($flow_id)__($pair)"
    let run_id = "run-orp"
    let result_id = "res-orp"
    let run_prefix = $"artifacts/($flow_id)/($pair)/($exec_id)"

    let manifest = {
        schema_version: 1
        generated_at: "2026-01-01T00:00:00Z"
        runs: {
            ($run_id): {id: $run_id, cell_id: $cell_id, execution_id: $exec_id}
        }
        cells: {
            ($cell_id): {id: $cell_id, flow_id: $flow_id, pair: $pair}
        }
        results: {
            ($result_id): {
                id: $result_id
                run_id: $run_id
                cell_id: $cell_id
                evidence: [
                    {
                        kind: "screenshot"
                        scope: "cypress"
                        logical_name: "foo.png"
                        path: "cypress/screenshots/foo.png"
                        availability: "artifact"
                        evidence_id: "ev-ss"
                    }
                ]
            }
        }
    }

    mkdir $pub_dir
    $manifest | to json --indent 2 | save ($pub_dir | path join "suite-manifest.v1.json")

    # Write the expected optimized files.
    let opt_ss_dir = ($opt_dir | path join $run_prefix "cypress/screenshots")
    mkdir $opt_ss_dir
    $"avif-bytes" | save ($opt_ss_dir | path join "foo.avif")
    $"webp-bytes" | save ($opt_ss_dir | path join "foo.webp")

    # Write an extra orphan file at a different run prefix (not referenced by evidence).
    let orphan_run = "artifacts/other-flow/other-pair/orphan-exec"
    let orphan_dir = ($opt_dir | path join $orphan_run "cypress/screenshots")
    mkdir $orphan_dir
    $"orphan-avif" | save ($orphan_dir | path join "orphan.avif")

    let result = (try { apply-media-projection $pub_dir $opt_dir; "ok" } catch {|e| $e.msg})

    ^rm -rf $tmp
    [
        (assert-truthy ($result | str contains "orphan")
            "fails with orphan message when extra optimized files exist")
        (assert-truthy ($result | str contains "orphan.avif")
            "error message mentions the orphan file")
    ]
}

def test-projected-row-no-png-or-mp4-variants [] {
    test-log "\n[test-projected-row-no-png-or-mp4-variants]"
    let work = (^mktemp -d | str trim)
    let fixtures = (
        $SUITE_PATH | path dirname | path dirname
        | path join "fixtures/optimized-media"
    )

    # Build pub dir: copy manifest and create raw marker files.
    mkdir ($work | path join "pub")
    ^cp ($fixtures | path join "raw-public-manifest.json") ($work | path join "pub/suite-manifest.v1.json")
    let run_prefix = "artifacts/login/nextcloud-v34/exec-fixture"
    mkdir ($work | path join "pub" | path join $run_prefix | path join "cypress/screenshots")
    mkdir ($work | path join "pub" | path join $run_prefix | path join "cypress/videos")
    "marker" | save -f ($work | path join "pub" | path join $run_prefix | path join "cypress/screenshots/sample.png")
    "marker" | save -f ($work | path join "pub" | path join $run_prefix | path join "cypress/videos/sample.mp4")

    # Build opt dir: copy pre-optimized tree.
    mkdir ($work | path join "opt")
    ^cp -r ($fixtures | path join "pre-optimized/artifacts") ($work | path join "opt/artifacts")

    apply-media-projection ($work | path join "pub") ($work | path join "opt")

    let projected = (open ($work | path join "pub/suite-manifest.v1.json"))
    let result = $projected.results.result-exec-fixture
    let ss_ev = ($result.evidence | where kind == "screenshot" | first)
    let vid_ev = ($result.evidence | where kind == "video" | first)

    let ss_variants = ($ss_ev.media_variants? | default [])
    let vid_variants = ($vid_ev.media_variants? | default [])

    let ss_no_png = not ($ss_variants | any {|v|
        ((($v.format? | default "") == "png") or (($v.mime? | default "") == "image/png"))
    })
    let ss_no_mp4 = not ($ss_variants | any {|v|
        ((($v.format? | default "") == "mp4") or (($v.mime? | default "") == "video/mp4"))
    })
    let vid_no_png = not ($vid_variants | any {|v|
        ((($v.format? | default "") == "png") or (($v.mime? | default "") == "image/png"))
    })
    let vid_no_mp4 = not ($vid_variants | any {|v|
        ((($v.format? | default "") == "mp4") or (($v.mime? | default "") == "video/mp4"))
    })

    ^rm -rf $work
    [
        (assert-truthy $ss_no_png "screenshot variants have no png format or image/png mime")
        (assert-truthy $ss_no_mp4 "screenshot variants have no mp4 format or video/mp4 mime")
        (assert-truthy $vid_no_png "video variants have no png format or image/png mime")
        (assert-truthy $vid_no_mp4 "video variants have no mp4 format or video/mp4 mime")
    ]
}

# --- derived-only invariant ---

def make-valid-screenshot-row [] {
    {
        kind: "screenshot"
        path: "cypress/screenshots/foo.avif"
        logical_name: "foo.avif"
        source_path: "cypress/screenshots/foo.png"
        media_variants: [
            {role: "primary",  path: "cypress/screenshots/foo.avif", format: "avif",  mime: "image/avif"}
            {role: "fallback", path: "cypress/screenshots/foo.webp", format: "webp",  mime: "image/webp"}
        ]
    }
}

def make-valid-video-row [] {
    {
        kind: "video"
        path: "cypress/videos/run.av1.webm"
        logical_name: "run.av1.webm"
        source_path: "cypress/videos/run.mp4"
        media_variants: [
            {role: "primary",  path: "cypress/videos/run.av1.webm", format: "av1-webm", mime: "video/webm", codecs: "av01"}
            {role: "fallback", path: "cypress/videos/run.vp9.webm", format: "vp9-webm", mime: "video/webm", codecs: "vp9"}
        ]
    }
}

def test-derived-only-passes-on-valid-screenshot-row [] {
    test-log "\n[test-derived-only-passes-on-valid-screenshot-row]"
    let row = (make-valid-screenshot-row)
    let ok = (try { assert-projected-media-row-derived-only $row; true } catch { false })
    [(assert-truthy $ok "valid projected screenshot row passes derived-only invariant")]
}

def test-derived-only-passes-on-valid-video-row [] {
    test-log "\n[test-derived-only-passes-on-valid-video-row]"
    let row = (make-valid-video-row)
    let ok = (try { assert-projected-media-row-derived-only $row; true } catch { false })
    [(assert-truthy $ok "valid projected video row passes derived-only invariant")]
}

def test-derived-only-passes-on-non-media-row [] {
    test-log "\n[test-derived-only-passes-on-non-media-row]"
    let row = {kind: "log", path: "docker/logs/foo.log"}
    let ok = (try { assert-projected-media-row-derived-only $row; true } catch { false })
    [(assert-truthy $ok "non-media row (kind=log) passes through without error")]
}

def test-derived-only-fails-on-screenshot-with-png-path [] {
    test-log "\n[test-derived-only-fails-on-screenshot-with-png-path]"
    let row = (make-valid-screenshot-row | upsert path "cypress/screenshots/foo.png")
    let err = (try { assert-projected-media-row-derived-only $row; "" } catch {|e| $e.msg})
    [
        (assert-truthy (not ($err | is-empty))
            "screenshot row with .png path is rejected")
        (assert-truthy ($err | str contains "path")
            "error mentions the path field")
        (assert-truthy ($err | str contains ".png")
            "error mentions the .png extension")
        (assert-truthy ($err | str contains "screenshot")
            "error mentions kind=screenshot")
    ]
}

def test-derived-only-fails-on-video-with-mp4-path [] {
    test-log "\n[test-derived-only-fails-on-video-with-mp4-path]"
    let row = (make-valid-video-row | upsert path "cypress/videos/run.mp4")
    let err = (try { assert-projected-media-row-derived-only $row; "" } catch {|e| $e.msg})
    [
        (assert-truthy (not ($err | is-empty))
            "video row with .mp4 path is rejected")
        (assert-truthy ($err | str contains "path")
            "error mentions the path field")
        (assert-truthy ($err | str contains ".mp4")
            "error mentions the .mp4 extension")
        (assert-truthy ($err | str contains "video")
            "error mentions kind=video")
    ]
}

def test-derived-only-fails-on-mismatched-logical-name [] {
    test-log "\n[test-derived-only-fails-on-mismatched-logical-name]"
    let row = (make-valid-screenshot-row | upsert logical_name "foo.png")
    let err = (try { assert-projected-media-row-derived-only $row; "" } catch {|e| $e.msg})
    [
        (assert-truthy (not ($err | is-empty))
            "screenshot row with .png logical_name is rejected")
        (assert-truthy ($err | str contains "logical_name")
            "error mentions logical_name field")
        (assert-truthy ($err | str contains ".png")
            "error mentions the .png extension")
    ]
}

def test-derived-only-fails-on-bad-source-path-extension [] {
    test-log "\n[test-derived-only-fails-on-bad-source-path-extension]"
    let row = (make-valid-screenshot-row | upsert source_path "cypress/screenshots/foo.jpg")
    let err = (try { assert-projected-media-row-derived-only $row; "" } catch {|e| $e.msg})
    [
        (assert-truthy (not ($err | is-empty))
            "screenshot row with .jpg source_path is rejected")
        (assert-truthy ($err | str contains "source_path")
            "error mentions source_path field")
        (assert-truthy ($err | str contains ".png")
            "error mentions expected .png extension")
    ]
}

def test-derived-only-fails-on-missing-fallback-variant [] {
    test-log "\n[test-derived-only-fails-on-missing-fallback-variant]"
    let row = (make-valid-screenshot-row | upsert media_variants [
        {role: "primary", path: "cypress/screenshots/foo.avif", format: "avif", mime: "image/avif"}
    ])
    let err = (try { assert-projected-media-row-derived-only $row; "" } catch {|e| $e.msg})
    [
        (assert-truthy (not ($err | is-empty))
            "screenshot row with only 1 variant is rejected")
        (assert-truthy ($err | str contains "media_variants")
            "error mentions media_variants")
        (assert-truthy ($err | str contains "1")
            "error references the actual count of 1")
    ]
}

def test-derived-only-fails-on-wrong-fallback-format [] {
    test-log "\n[test-derived-only-fails-on-wrong-fallback-format]"
    let row = (make-valid-screenshot-row | upsert media_variants [
        {role: "primary",  path: "cypress/screenshots/foo.avif", format: "avif", mime: "image/avif"}
        {role: "fallback", path: "cypress/screenshots/foo.png",  format: "webp", mime: "image/webp"}
    ])
    let err = (try { assert-projected-media-row-derived-only $row; "" } catch {|e| $e.msg})
    [
        (assert-truthy (not ($err | is-empty))
            "screenshot row with fallback path ending .png is rejected")
        (assert-truthy ($err | str contains "fallback")
            "error mentions fallback role")
        (assert-truthy ($err | str contains ".webp")
            "error mentions expected .webp extension")
    ]
}

def test-derived-only-fails-on-path-mismatch-with-primary-variant [] {
    test-log "\n[test-derived-only-fails-on-path-mismatch-with-primary-variant]"
    let row = (make-valid-screenshot-row | upsert media_variants [
        {role: "primary",  path: "cypress/screenshots/bar.avif", format: "avif", mime: "image/avif"}
        {role: "fallback", path: "cypress/screenshots/bar.webp", format: "webp", mime: "image/webp"}
    ])
    let err = (try { assert-projected-media-row-derived-only $row; "" } catch {|e| $e.msg})
    [
        (assert-truthy (not ($err | is-empty))
            "row with path != media_variants[0].path is rejected")
        (assert-truthy ($err | str contains "cross-consistency")
            "error references cross-consistency check")
        (assert-truthy ($err | str contains "media_variants[0]")
            "error references media_variants[0].path")
    ]
}

def test-derived-only-fails-on-stray-png-in-other-field [] {
    test-log "\n[test-derived-only-fails-on-stray-png-in-other-field]"
    let row = (make-valid-screenshot-row | insert custom_field "cypress/screenshots/stray.png")
    let err = (try { assert-projected-media-row-derived-only $row; "" } catch {|e| $e.msg})
    [
        (assert-truthy (not ($err | is-empty))
            "screenshot row with stray .png in custom_field is rejected")
        (assert-truthy ($err | str contains "custom_field")
            "error names the offending field")
        (assert-truthy ($err | str contains ".png")
            "error mentions .png raw extension")
    ]
}

def main [] {
    test-log "=== site/project-media tests ==="
    let results = (
        (test-check-path-safe-ok)
        | append (test-check-path-safe-empty)
        | append (test-check-path-safe-absolute)
        | append (test-check-path-safe-traversal)
        | append (test-check-kind-path-match-ok)
        | append (test-check-kind-path-match-bad)
        | append (test-derive-screenshot-variants)
        | append (test-derive-video-variants)
        | append (test-derive-unknown-kind-returns-null)
        | append (test-derive-logical-name-is-filename)
        | append (test-resolve-run-prefix-ok)
        | append (test-resolve-run-prefix-missing-components)
        | append (test-project-non-media-passthrough)
        | append (test-project-screenshot-success)
        | append (test-project-video-success)
        | append (test-project-fails-when-primary-missing)
        | append (test-project-fails-when-fallback-missing)
        | append (test-project-rejects-absolute-ev-path)
        | append (test-project-rejects-traversal-ev-path)
        | append (test-project-rejects-kind-mismatch)
        | append (test-apply-media-projection-full)
        | append (test-apply-media-projection-fails-missing-optimized)
        | append (test-apply-media-projection-missing-manifest-fails)
        | append (test-apply-media-projection-missing-opt-dir-fails)
        | append (test-manifest-has-media-rows-true)
        | append (test-manifest-has-media-rows-false-no-media)
        | append (test-manifest-has-media-rows-false-no-manifest)
        | append (test-manifest-has-media-rows-video)
        | append (test-assert-under-pub-dir-ok)
        | append (test-assert-under-pub-dir-escapes-rejected)
        | append (test-apply-media-projection-orphan-rejected)
        | append (test-projected-row-no-png-or-mp4-variants)
        | append (test-derived-only-passes-on-valid-screenshot-row)
        | append (test-derived-only-passes-on-valid-video-row)
        | append (test-derived-only-passes-on-non-media-row)
        | append (test-derived-only-fails-on-screenshot-with-png-path)
        | append (test-derived-only-fails-on-video-with-mp4-path)
        | append (test-derived-only-fails-on-mismatched-logical-name)
        | append (test-derived-only-fails-on-bad-source-path-extension)
        | append (test-derived-only-fails-on-missing-fallback-variant)
        | append (test-derived-only-fails-on-wrong-fallback-format)
        | append (test-derived-only-fails-on-path-mismatch-with-primary-variant)
        | append (test-derived-only-fails-on-stray-png-in-other-field)
    ) | flatten
    run-suite "site/project-media" $SUITE_PATH $results
}
