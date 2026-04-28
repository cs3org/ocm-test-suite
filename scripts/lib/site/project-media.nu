# Site publish media projection.
# Rewrites media evidence rows in the public suite manifest to use optimized
# variants (AVIF/WebP screenshots, AV1-WebM/VP9-WebM videos), copies derived
# media into the public artifact tree, and removes raw PNG/MP4 from public.
#
# Exported:
#   check-path-safe                           - reject unsafe relative paths
#   check-kind-path-match                     - reject kind/extension mismatches in evidence
#   derive-media-variants                     - compute optimized paths for one evidence row
#   resolve-run-prefix                        - artifacts/<flow>/<pair>/<exec_id> from manifest
#   project-one-evidence-item                 - project one evidence row; returns ops + error
#   manifest-has-media-rows                   - true when public manifest has screenshot/video evidence
#   assert-under-pub-dir                      - reject a path that escapes pub_dir (exported for tests)
#   assert-projected-media-row-derived-only   - reject any row that leaks raw .png/.mp4 into displayable fields
#   apply-media-projection                    - top-level: read manifest, project, copy, save

# Validate a relative path used in evidence or optimized data.
# Returns "" when safe, or an error message when unsafe.
export def check-path-safe [p: string]: nothing -> string {
    if ($p | is-empty) { return "empty path rejected" }
    if ($p | str starts-with "/") { return $"absolute path rejected: ($p)" }
    let parts = ($p | split row "/")
    if ".." in $parts { return $"path traversal rejected: ($p)" }
    ""
}

# Validate that a media evidence kind matches the expected extension.
# Returns "" when consistent, or an error message when not.
# kind=screenshot expects .png source; kind=video expects .mp4 source.
export def check-kind-path-match [kind: string, ev_path: string]: nothing -> string {
    let lp = ($ev_path | str downcase)
    if $kind == "screenshot" {
        if not ($lp | str ends-with ".png") {
            return $"kind=screenshot but path does not end with .png: ($ev_path)"
        }
    } else if $kind == "video" {
        if not ($lp | str ends-with ".mp4") {
            return $"kind=video but path does not end with .mp4: ($ev_path)"
        }
    }
    ""
}

# Derive run-relative optimized paths for one evidence row.
# ev_path: run-relative raw path e.g. "cypress/screenshots/.../foo.png"
# kind:    "screenshot" or "video"
# Returns a flat record with primary_rel, fallback_rel, primary_fmt,
# primary_mime, primary_codecs, fallback_fmt, fallback_mime, fallback_codecs,
# or null for unrecognized kind. codecs is null for image kinds.
export def derive-media-variants [ev_path: string, kind: string]: nothing -> any {
    if ($ev_path | is-empty) { return null }
    let p = ($ev_path | path parse)
    let stem = $p.stem
    let parent = $p.parent
    let stem_path = if ($parent | is-empty) { $stem } else { $parent | path join $stem }

    if $kind == "screenshot" {
        {
            primary_rel:    ($stem_path + ".avif")
            fallback_rel:   ($stem_path + ".webp")
            primary_fmt:    "avif"
            primary_mime:   "image/avif"
            primary_codecs: null
            fallback_fmt:   "webp"
            fallback_mime:  "image/webp"
            fallback_codecs: null
        }
    } else if $kind == "video" {
        {
            primary_rel:    ($stem_path + ".av1.webm")
            fallback_rel:   ($stem_path + ".vp9.webm")
            primary_fmt:    "av1-webm"
            primary_mime:   "video/webm"
            primary_codecs: "av01"
            fallback_fmt:   "vp9-webm"
            fallback_mime:  "video/webm"
            fallback_codecs: "vp9"
        }
    } else {
        null
    }
}

# Resolve the artifacts/<flow>/<pair>/<exec_id> run prefix for a result.
# Uses the manifest's runs and cells records to look up context from result.
# Returns an empty string when any component is missing.
export def resolve-run-prefix [result: record, manifest: record]: nothing -> string {
    let run_id = ($result.run_id? | default "")
    let cell_id = ($result.cell_id? | default "")
    let runs = ($manifest.runs? | default {})
    let cells = ($manifest.cells? | default {})
    let run = ($runs | get --optional $run_id | default {})
    let exec_id = ($run.execution_id? | default "")
    let cell = ($cells | get --optional $cell_id | default {})
    let flow_id = ($cell.flow_id? | default "")
    let pair = ($cell.pair? | default "")
    if ($flow_id | is-empty) or ($pair | is-empty) or ($exec_id | is-empty) {
        return ""
    }
    $"artifacts/($flow_id)/($pair)/($exec_id)"
}

# Project one evidence item using the optimized aggregate in opt_agg_dir.
# Non-media items (kind != screenshot/video) pass through unchanged with no ops.
# run_prefix: "artifacts/<flow>/<pair>/<exec_id>"
# opt_agg_dir: root of the optimized aggregate (contains artifacts/ subtree)
# Returns {item, error, copy_ops, remove_ops}
#   copy_ops:   list of {src_abs, dst_rel} - dst_rel is relative to pub_dir
#   remove_ops: list of strings - each relative to pub_dir
export def project-one-evidence-item [
    ev: record,
    run_prefix: string,
    opt_agg_dir: string,
]: nothing -> record {
    let no_ops = {item: $ev, error: "", copy_ops: [], remove_ops: []}
    let kind = ($ev.kind? | default "")
    let ev_path = ($ev.path? | default "")

    if $kind != "screenshot" and $kind != "video" {
        return $no_ops
    }

    # Validate the raw evidence path.
    let safe_err = (check-path-safe $ev_path)
    if not ($safe_err | is-empty) {
        return ($no_ops | upsert error $"evidence path unsafe: ($safe_err)")
    }
    let kind_err = (check-kind-path-match $kind $ev_path)
    if not ($kind_err | is-empty) {
        return ($no_ops | upsert error $kind_err)
    }

    # Validate the run_prefix components.
    let prefix_err = (check-path-safe $run_prefix)
    if not ($prefix_err | is-empty) {
        return ($no_ops | upsert error $"run_prefix unsafe: ($prefix_err)")
    }
    if ($run_prefix | is-empty) {
        return ($no_ops | upsert error $"cannot resolve run prefix for evidence: ($ev_path)")
    }

    let variants = (derive-media-variants $ev_path $kind)
    if $variants == null {
        return ($no_ops | upsert error $"cannot derive variants for kind=($kind)")
    }

    # Locate optimized files in the aggregate.
    let pri_abs = ($opt_agg_dir | path join $run_prefix | path join $variants.primary_rel)
    let fal_abs = ($opt_agg_dir | path join $run_prefix | path join $variants.fallback_rel)

    if not ($pri_abs | path exists) {
        return ($no_ops | upsert error (
            $"required primary optimized file missing: ($variants.primary_rel) for ($ev_path)"
        ))
    }
    if not ($fal_abs | path exists) {
        return ($no_ops | upsert error (
            $"required fallback optimized file missing: ($variants.fallback_rel) for ($ev_path)"
        ))
    }

    # Rewrite the evidence row.
    # media_variants is an ordered array: primary first, fallback second.
    # codecs is included only when non-null (video kinds).
    let new_logical = ($variants.primary_rel | path basename)
    let pri_base = {
        role: "primary"
        path: $variants.primary_rel
        format: $variants.primary_fmt
        mime: $variants.primary_mime
    }
    let fal_base = {
        role: "fallback"
        path: $variants.fallback_rel
        format: $variants.fallback_fmt
        mime: $variants.fallback_mime
    }
    let pri_item = if $variants.primary_codecs != null {
        $pri_base | insert codecs $variants.primary_codecs
    } else { $pri_base }
    let fal_item = if $variants.fallback_codecs != null {
        $fal_base | insert codecs $variants.fallback_codecs
    } else { $fal_base }
    let projected = (
        $ev
        | upsert path $variants.primary_rel
        | upsert logical_name $new_logical
        | upsert source_path $ev_path
        | upsert media_variants [$pri_item $fal_item]
    )

    # Abort publish if the projection logic produces a row that still leaks raw paths.
    assert-projected-media-row-derived-only $projected

    let copy_ops = [
        {
            src_abs: $pri_abs
            dst_rel: ($run_prefix | path join $variants.primary_rel)
        }
        {
            src_abs: $fal_abs
            dst_rel: ($run_prefix | path join $variants.fallback_rel)
        }
    ]
    let remove_ops = [($run_prefix | path join $ev_path)]

    {item: $projected, error: "", copy_ops: $copy_ops, remove_ops: $remove_ops}
}

# Project all evidence rows for one result record.
# Returns {result, copy_ops, remove_ops, errors}
def project-result-evidence [
    result: record,
    run_prefix: string,
    opt_agg_dir: string,
]: nothing -> record {
    let evidence = ($result.evidence? | default [])
    mut new_evidence = []
    mut copy_ops = []
    mut remove_ops = []
    mut errors = []

    for ev in $evidence {
        let out = (project-one-evidence-item $ev $run_prefix $opt_agg_dir)
        $new_evidence = ($new_evidence | append $out.item)
        $copy_ops = ($copy_ops | append $out.copy_ops)
        $remove_ops = ($remove_ops | append $out.remove_ops)
        if not ($out.error | is-empty) {
            $errors = ($errors | append $out.error)
        }
    }

    {
        result: ($result | upsert evidence $new_evidence)
        copy_ops: $copy_ops
        remove_ops: $remove_ops
        errors: $errors
    }
}

# Return true when the public manifest at pub_dir contains any screenshot
# or video evidence row in any result. Returns false when the manifest is
# absent, has no results, or all evidence rows are non-media.
export def manifest-has-media-rows [pub_dir: string]: nothing -> bool {
    let manifest_path = ($pub_dir | path join "suite-manifest.v1.json")
    if not ($manifest_path | path exists) { return false }
    let manifest = (open $manifest_path)
    let results = ($manifest.results? | default {})
    $results | transpose k v | any {|rp|
        let ev = ($rp.v.evidence? | default [])
        $ev | any {|e|
            let kind = ($e.kind? | default "")
            ($kind == "screenshot") or ($kind == "video")
        }
    }
}

# Defensive containment check: assert dst is under pub_dir.
# Errors with a clear message when dst escapes pub_dir.
# This is dead code in normal projection (upstream path safety covers it)
# but is required by the Security and Safety contract.
export def assert-under-pub-dir [pub_dir: string, dst: string] {
    let pub_exp = ($pub_dir | path expand)
    let dst_exp = ($dst | path expand)
    if not ($dst_exp | str starts-with $"($pub_exp)/") {
        error make {msg: (
            $"apply-media-projection: destination path escapes pub_dir: "
            + $"dst=($dst_exp) pub_dir=($pub_exp)"
        )}
    }
}

# Assert that a single projected media evidence row obeys the derived-only
# invariant: every displayable field references the derived primary; only
# source_path may reference the raw capture. Errors with a precise field-by-
# field message on any violation. Non-media rows pass through unchanged.
export def assert-projected-media-row-derived-only [row: record] {
    let kind = ($row.kind? | default "")
    if $kind != "screenshot" and $kind != "video" { return }

    let primary_ext  = if $kind == "screenshot" { ".avif" }     else { ".av1.webm" }
    let fallback_ext = if $kind == "screenshot" { ".webp" }     else { ".vp9.webm" }
    let raw_ext      = if $kind == "screenshot" { ".png" }      else { ".mp4" }

    let ev_path = ($row.path? | default "")
    let path_display = if ($ev_path | is-empty) { "<missing>" } else { $ev_path }

    mut violations = []

    # Check 2: row.path must end in derived primary ext.
    if not ($ev_path | str ends-with $primary_ext) {
        $violations = ($violations | append $"path: expected to end with ($primary_ext), got '($ev_path)'")
    }

    # Check 3: row.logical_name (if present and non-empty) must match primary ext.
    let logical = ($row.logical_name? | default "")
    if not ($logical | is-empty) {
        if not ($logical | str ends-with $primary_ext) {
            $violations = ($violations | append $"logical_name: expected to end with ($primary_ext), got '($logical)'")
        }
    }

    # Check 4: row.source_path (if present) must end in the kind-appropriate raw ext.
    let src = ($row.source_path? | default "")
    if not ($src | is-empty) {
        if not ($src | str ends-with $raw_ext) {
            $violations = ($violations | append $"source_path: expected to end with ($raw_ext), got '($src)'")
        }
    }

    # Check 5: media_variants must be exactly two entries ordered primary then fallback.
    let variants = ($row.media_variants? | default [])
    let variant_count = ($variants | length)
    if $variant_count != 2 {
        $violations = ($violations | append (
            $"media_variants: expected exactly 2 entries \(primary + fallback\), got ($variant_count)"
        ))
    } else {
        let pri = ($variants | get 0)
        let fal = ($variants | get 1)

        let pri_role = ($pri.role? | default "")
        if $pri_role != "primary" {
            $violations = ($violations | append $"media_variants[0].role: expected 'primary', got '($pri_role)'")
        }
        let pri_path = ($pri.path? | default "")
        if not ($pri_path | str ends-with $primary_ext) {
            $violations = ($violations | append (
                $"media_variants[0].path: expected to end with ($primary_ext), got '($pri_path)'"
            ))
        }

        let fal_role = ($fal.role? | default "")
        if $fal_role != "fallback" {
            $violations = ($violations | append $"media_variants[1].role: expected 'fallback', got '($fal_role)'")
        }
        let fal_path = ($fal.path? | default "")
        if not ($fal_path | str ends-with $fallback_ext) {
            $violations = ($violations | append (
                $"media_variants[1].path: expected to end with ($fallback_ext) for ($kind) fallback, got '($fal_path)'"
            ))
        }

        # Check 6: cross-consistency - row.path must equal media_variants[0].path.
        if $ev_path != $pri_path {
            $violations = ($violations | append (
                $"cross-consistency: path '($ev_path)' does not match media_variants[0].path '($pri_path)'"
            ))
        }
    }

    # Check 7: no top-level field (except source_path) may be a string ending in .png or .mp4.
    for col in ($row | columns) {
        if $col != "source_path" {
            let val = ($row | get $col)
            if ($val | describe) == "string" {
                if (($val | str ends-with ".png") or ($val | str ends-with ".mp4")) {
                    $violations = ($violations | append (
                        $"($col): field value ends with raw extension, got '($val)'"
                    ))
                }
            }
        }
    }

    if ($violations | is-empty) { return }

    let lines = ($violations | each {|v| $"  - ($v)"} | str join "\n")
    error make {msg: (
        $"assert-projected-media-row-derived-only: row violates derived-only invariant for kind=($kind), path=($path_display):\n"
        + $lines
    )}
}

# Apply optimized media projection to the public suite manifest.
# Reads pub_dir/suite-manifest.v1.json, rewrites media evidence rows,
# copies optimized files into pub_dir/artifacts/..., removes raw media,
# and saves the projected manifest in-place.
# Fails hard if any required optimized variants are missing.
export def apply-media-projection [
    pub_dir: string,
    opt_agg_dir: string,
] {
    let manifest_path = ($pub_dir | path join "suite-manifest.v1.json")
    if not ($manifest_path | path exists) {
        error make {msg: $"apply-media-projection: public manifest not found: ($manifest_path)"}
    }
    if not ($opt_agg_dir | path exists) {
        error make {msg: $"apply-media-projection: optimized media dir not found: ($opt_agg_dir)"}
    }

    let manifest = (open $manifest_path)
    let results = ($manifest.results? | default {})

    mut new_results = {}
    mut all_copy_ops = []
    mut all_remove_ops = []
    mut all_errors = []

    for rp in ($results | transpose k v) {
        let result_id = $rp.k
        let result = $rp.v
        let run_prefix = (resolve-run-prefix $result $manifest)
        let out = (project-result-evidence $result $run_prefix $opt_agg_dir)
        $new_results = ($new_results | upsert $result_id $out.result)
        $all_copy_ops = ($all_copy_ops | append $out.copy_ops)
        $all_remove_ops = ($all_remove_ops | append $out.remove_ops)
        $all_errors = ($all_errors | append $out.errors)
    }

    if not ($all_errors | is-empty) {
        let msg = ($all_errors | str join "\n  ")
        error make {msg: $"apply-media-projection: missing required optimized media:\n  ($msg)"}
    }

    # Task F: reject orphan optimized files not referenced by any evidence row.
    # Walk opt_agg_dir/artifacts for known derived extensions and reject any file
    # whose absolute path is not in the expected copy set.
    let expected_abs = ($all_copy_ops | each {|op| $op.src_abs})
    let opt_abs = ($opt_agg_dir | path expand)
    let found_opt_files = (
        (try { glob ($opt_abs | path join "artifacts/**/*.avif") } catch { [] })
        | append (try { glob ($opt_abs | path join "artifacts/**/*.webp") } catch { [] })
        | append (try { glob ($opt_abs | path join "artifacts/**/*.webm") } catch { [] })
    )
    let orphans = ($found_opt_files | where {|f| not ($f in $expected_abs)})
    if ($orphans | is-not-empty) {
        let orphan_list = ($orphans | each {|f|
            let prefix = $"($opt_abs)/"
            $f | str replace $prefix ""
        } | str join "\n  ")
        error make {msg: $"apply-media-projection: orphan optimized files not referenced by any evidence row:\n  ($orphan_list)"}
    }

    # Copy optimized files into the public artifacts tree.
    for op in $all_copy_ops {
        let dst = ($pub_dir | path join $op.dst_rel)
        # Defensive containment check (dead code path in normal flow).
        assert-under-pub-dir $pub_dir $dst
        mkdir ($dst | path dirname)
        cp $op.src_abs $dst
    }

    # Remove raw media from the public artifacts tree.
    for rel in $all_remove_ops {
        let raw_path = ($pub_dir | path join $rel)
        # Defensive containment check (dead code path in normal flow).
        assert-under-pub-dir $pub_dir $raw_path
        if ($raw_path | path exists) {
            rm $raw_path
        }
    }

    # Save the projected manifest.
    let projected = ($manifest | upsert results $new_results)
    $projected | to json --indent 2 | save --force $manifest_path

    let copy_count = ($all_copy_ops | length)
    let remove_count = ($all_remove_ops | length)
    print --stderr $"Media projection applied: ($copy_count) optimized files copied, ($remove_count) raw files removed"
}
