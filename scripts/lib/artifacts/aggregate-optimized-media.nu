# Aggregate per-cell optimized-media artifacts into one bundle and summary.
# Each input cell dir must contain meta/optimized-media-cell.v1.json.
# Only derived media files are merged; raw source media is never touched.
#
# Exported surfaces:
#   validate-optimized-path       - reject unsafe paths
#   check-kind-ext-match          - reject kind/extension mismatches
#   read-cell-optimized-manifest  - read per-cell manifest or null
#   write-optimized-summary       - write meta/optimized-media-summary.v1.json
#   create-optimized-archive      - create optimized-media-artifacts.tar.zst
#   aggregate-optimized-media-cells - main orchestrator

use ../time/utc.nu [utc-now]
use ../ci/zstd.nu [build-zstd-flags default_zstd_archive_policy]

# Reject paths with traversal sequences, absolute references, or empty strings.
export def validate-optimized-path [p: string] {
    if ($p | is-empty) {
        error make {msg: "aggregate-optimized-media: empty optimized_path rejected"}
    }
    if ($p | str starts-with "/") {
        error make {msg: $"aggregate-optimized-media: absolute path rejected: ($p)"}
    }
    let parts = ($p | split row "/")
    if ".." in $parts {
        error make {msg: $"aggregate-optimized-media: path traversal rejected: ($p)"}
    }
}

# Check that a media kind is consistent with its optimized_path extension.
# Returns an empty string when consistent, or an error message when not.
# Only performs cheap local extension checks against the two known kind sets.
export def check-kind-ext-match [kind: string, optimized_path: string]: nothing -> string {
    let p = ($optimized_path | str downcase)
    if $kind == "screenshot" {
        if ($p | str ends-with ".webm") {
            return $"kind=screenshot but optimized_path ends with .webm: ($optimized_path)"
        }
    } else if $kind == "video" {
        if (($p | str ends-with ".avif") or ($p | str ends-with ".webp")) {
            return $"kind=video but optimized_path has image extension: ($optimized_path)"
        }
    }
    ""
}

# Read meta/optimized-media-cell.v1.json from a cell artifact dir.
# Returns null when the manifest file does not exist.
export def read-cell-optimized-manifest [cell_dir: string]: nothing -> any {
    let path = ($cell_dir | path join "meta/optimized-media-cell.v1.json")
    if not ($path | path exists) { null } else { open $path }
}

# Build a per-cell summary record.
def build-cell-summary [cell_key: string, cell_dir: string, manifest: any] {
    if $manifest == null {
        return {
            cell_key: $cell_key,
            cell_dir: $cell_dir,
            manifest_found: false,
            status: "missing-manifest",
            optimizer_image: "",
            item_count: 0,
            optimized_count: 0,
            failed_count: 0,
            no_source_media: false,
            items: [],
        }
    }
    let status = ($manifest.status? | default "unknown")
    let items = ($manifest.items? | default [])
    let optimized_count = ($items | where {|r| $r.status? == "optimized"} | length)
    let failed_count = ($items | where {|r| $r.status? == "failed"} | length)
    {
        cell_key: $cell_key,
        cell_dir: $cell_dir,
        manifest_found: true,
        status: $status,
        optimizer_image: ($manifest.optimizer_image? | default ""),
        item_count: ($items | length),
        optimized_count: $optimized_count,
        failed_count: $failed_count,
        no_source_media: ($status == "no-source-media"),
        items: $items,
    }
}

# Validate all items in one cell manifest; return list of error strings.
def validate-manifest-items [cell_key: string, manifest: record]: nothing -> list<string> {
    let items = ($manifest.items? | default [])
    mut errors = []
    for item in $items {
        let opath = ($item.optimized_path? | default "")
        let path_err = (try {
            validate-optimized-path $opath
            null
        } catch {|e| $e.msg})
        if $path_err != null {
            $errors = ($errors | append $"cell ($cell_key): ($path_err)")
        }
        let kind = ($item.kind? | default "")
        let ext_err = (check-kind-ext-match $kind $opath)
        if not ($ext_err | is-empty) {
            $errors = ($errors | append $"cell ($cell_key): ($ext_err)")
        }
    }

    # Variant completeness: each source_path must have exactly one primary and one fallback.
    let by_source = ($items | group-by source_path)
    for entry in ($by_source | items {|src group| {src: $src, group: $group}}) {
        let src = $entry.src
        let group = $entry.group
        let primaries = ($group | where {|r| ($r.role? | default "") == "primary"} | length)
        let fallbacks = ($group | where {|r| ($r.role? | default "") == "fallback"} | length)
        if $primaries == 0 {
            $errors = ($errors | append $"cell ($cell_key): source_path ($src) has no primary role item")
        } else if $primaries > 1 {
            $errors = ($errors | append $"cell ($cell_key): source_path ($src) has ($primaries) primary role items, expected exactly 1")
        }
        if $fallbacks == 0 {
            $errors = ($errors | append $"cell ($cell_key): source_path ($src) has no fallback role item")
        } else if $fallbacks > 1 {
            $errors = ($errors | append $"cell ($cell_key): source_path ($src) has ($fallbacks) fallback role items, expected exactly 1")
        }
    }

    $errors
}

# Check that each optimized item in a manifest exists on disk; return error strings.
def validate-manifest-disk-files [cell_key: string, cell_dir: string, manifest: record]: nothing -> list<string> {
    let items = ($manifest.items? | default [])
    let cell_abs = ($cell_dir | path expand)
    mut errors = []
    for item in $items {
        if ($item.status? | default "") == "optimized" {
            let opath = ($item.optimized_path? | default "")
            if not ($opath | is-empty) {
                let abs = ($cell_abs | path join $opath)
                if not ($abs | path exists) {
                    $errors = ($errors | append $"cell ($cell_key): optimized file missing on disk: ($opath)")
                }
            }
        }
    }
    $errors
}

# Return {src_abs, dest_rel} for each successfully optimized item in a manifest.
def collect-cell-media-files [cell_dir: string, manifest: record] {
    let items = ($manifest.items? | default [])
    let cell_abs = ($cell_dir | path expand)
    let optimized = ($items | where {|r| $r.status? == "optimized"})
    $optimized | each {|item|
        let opath = ($item.optimized_path? | default "")
        {src_abs: ($cell_abs | path join $opath), dest_rel: $opath}
    }
}

# Copy one cell's optimized media into the output directory.
# Files land at out_dir/<item.optimized_path> which already starts with artifacts/...
# preserving the truthful run-relative artifact tree layout.
def copy-cell-media-to-out [
    cell_dir: string,
    manifest: any,
    out_dir: string,
] {
    if $manifest == null { return }
    let media_files = (collect-cell-media-files $cell_dir $manifest)
    for f in $media_files {
        if ($f.src_abs | path exists) {
            let dest_abs = ($out_dir | path join $f.dest_rel)
            mkdir ($dest_abs | path dirname)
            ^cp $f.src_abs $dest_abs
        } else {
            error make {msg: $"copy-cell-media-to-out: optimized file missing on disk (should have been caught by pre-copy validation): ($f.src_abs)"}
        }
    }
}

# Write meta/optimized-media-summary.v1.json into out_dir from cell summaries.
# Returns the path to the written file.
export def write-optimized-summary [
    cell_summaries: list<record>,
    out_dir: string,
]: nothing -> string {
    let generated_at = (utc-now)
    let cells_found = ($cell_summaries | length)
    let cells_without_media = ($cell_summaries | where {|s| $s.no_source_media} | length)
    let cells_missing = ($cell_summaries | where {|s| not $s.manifest_found} | length)
    let cells_with_media = ($cells_found - $cells_without_media - $cells_missing)

    let all_items = ($cell_summaries | each {|s| $s.items} | flatten)
    let optimized_count = ($all_items | where {|r| $r.status? == "optimized"} | length)
    let failed_count = ($all_items | where {|r| $r.status? == "failed"} | length)

    let optimizer_images = (
        $cell_summaries
        | each {|s| $s.optimizer_image}
        | where {|img| not ($img | is-empty)}
        | uniq
        | sort
    )

    let summary = {
        schema_version: 1,
        generated_at: $generated_at,
        cells_found: $cells_found,
        cells_with_media: $cells_with_media,
        cells_without_media: $cells_without_media,
        cells_missing_manifest: $cells_missing,
        item_counts: {
            optimized: $optimized_count,
            failed: $failed_count,
        },
        cell_counts_by_status: {
            no_source_media: $cells_without_media,
            missing_manifest: $cells_missing,
        },
        optimizer_images: $optimizer_images,
        cell_summaries: ($cell_summaries | each {|s| {
            cell_key: $s.cell_key,
            manifest_found: $s.manifest_found,
            status: $s.status,
            optimizer_image: $s.optimizer_image,
            item_count: $s.item_count,
            optimized_count: $s.optimized_count,
            failed_count: $s.failed_count,
        }}),
    }

    let meta_dir = ($out_dir | path join "meta")
    mkdir $meta_dir
    let path = ($meta_dir | path join "optimized-media-summary.v1.json")
    $summary | to json --indent 2 | save --force $path
    $path
}

# Create optimized-media-artifacts.tar.zst from the artifacts subtree.
# archive_tree: the artifacts/ directory to compress (must already exist).
# zstd_policy: compression tuning record with level, threads, checksum fields.
#   Defaults to default_zstd_archive_policy when null.
# Returns the path to the created archive file.
export def create-optimized-archive [
    archive_tree: string,
    out_dir: string,
    --zstd-policy: any = null,
]: nothing -> string {
    let out_path = ($out_dir | path join "optimized-media-artifacts.tar.zst")
    let tar_check = (try {
        ^tar --version | complete
    } catch {
        {exit_code: 127, stdout: "", stderr: "tar not found"}
    })
    if $tar_check.exit_code != 0 {
        error make {msg: "create-optimized-archive: tar is required but not available"}
    }
    let zstd_check = (try {
        ^zstd --version | complete
    } catch {
        {exit_code: 127, stdout: "", stderr: "zstd not found"}
    })
    if $zstd_check.exit_code != 0 {
        error make {msg: "create-optimized-archive: zstd is required but not available"}
    }
    let eff_policy = ($zstd_policy | default $default_zstd_archive_policy)
    let zstd_flags = (build-zstd-flags $eff_policy)

    # Write to a temp path first to avoid self-archival if out_dir is under archive_tree.
    let tmp_path = (^mktemp | str trim)
    let result = (try {
        ^tar -c -C ($archive_tree | path dirname) ($archive_tree | path basename)
            | ^zstd -f ...$zstd_flags -o $tmp_path
        | complete
    } catch {|e|
        {exit_code: 1, stdout: "", stderr: $e.msg}
    })
    if $result.exit_code != 0 {
        try { ^rm -f $tmp_path } catch {}
        error make {msg: $"create-optimized-archive: failed: ($result.stderr)"}
    }
    mkdir $out_dir
    ^mv $tmp_path $out_path
    $out_path
}

# Aggregate per-cell optimized artifact dirs into one bundle.
# artifact_dirs: list of per-cell optimized artifact directory paths (sorted deterministically).
# out_dir: destination for archive, summary manifest, and unpacked artifacts tree.
# zstd_policy: compression tuning record forwarded to create-optimized-archive.
#   Defaults to default_zstd_archive_policy when null.
# Returns a record with aggregate stats and output paths.
export def aggregate-optimized-media-cells [
    artifact_dirs: list<string>,
    out_dir: string,
    --no-archive,          # skip creating optimized-media-artifacts.tar.zst
    --zstd-policy: any = null,
]: nothing -> record {
    if ($artifact_dirs | is-empty) {
        error make {msg: "aggregate-optimized-media-cells: no artifact directories provided"}
    }

    mkdir $out_dir
    let artifacts_tree = ($out_dir | path join "artifacts")
    mkdir $artifacts_tree

    # Read all manifests; sort dirs for deterministic output order.
    let dirs_sorted = ($artifact_dirs | sort)
    let cell_data = ($dirs_sorted | each {|dir|
        let cell_key = ($dir | path basename)
        let manifest = (read-cell-optimized-manifest $dir)
        let summary = (build-cell-summary $cell_key $dir $manifest)
        {cell_key: $cell_key, dir: $dir, manifest: $manifest, summary: $summary}
    })

    # Validate items in each manifest (path safety, kind/ext match, disk existence).
    mut validation_errors = []
    for cd in $cell_data {
        if $cd.manifest != null {
            let errs = (validate-manifest-items $cd.cell_key $cd.manifest)
            $validation_errors = ($validation_errors | append $errs)
            let disk_errs = (validate-manifest-disk-files $cd.cell_key $cd.dir $cd.manifest)
            $validation_errors = ($validation_errors | append $disk_errs)
        }
    }

    # Detect duplicate optimized_path values across different cells.
    let all_paths = ($cell_data | each {|cd|
        if $cd.manifest == null {
            []
        } else {
            let items = ($cd.manifest.items? | default [])
            $items | each {|item|
                {
                    cell_key: $cd.cell_key,
                    optimized_path: ($item.optimized_path? | default ""),
                }
            }
        }
    } | flatten)

    if ($all_paths | is-not-empty) {
        let path_groups = ($all_paths | group-by optimized_path)
        let dup_errors = ($path_groups | items {|opath entries|
            if ($entries | length) > 1 {
                let cells_str = ($entries | each {|e| $e.cell_key} | str join ", ")
                $"duplicate optimized_path ($opath) in cells: ($cells_str)"
            } else {
                null
            }
        } | where {|x| $x != null})
        $validation_errors = ($validation_errors | append $dup_errors)
    }

    if ($validation_errors | is-not-empty) {
        let err_str = ($validation_errors | str join "\n  ")
        error make {msg: $"aggregate-optimized-media: validation failed:\n  ($err_str)"}
    }

    # Copy optimized media into the output dir.
    # Each item's optimized_path starts with artifacts/..., so files land at
    # out_dir/artifacts/<flow>/<pair>/<exec-id>/... preserving the run tree.
    for cd in $cell_data {
        copy-cell-media-to-out $cd.dir $cd.manifest $out_dir
    }

    # Write the summary manifest.
    let cell_summaries = ($cell_data | each {|cd| $cd.summary})
    let summary_path = (write-optimized-summary $cell_summaries $out_dir)

    # Create the archive unless skipped.
    let archive_path = if not $no_archive {
        create-optimized-archive $artifacts_tree $out_dir --zstd-policy $zstd_policy
    } else {
        null
    }

    let cells_found = ($cell_summaries | length)
    let cells_without_media = ($cell_summaries | where {|s| $s.no_source_media} | length)
    let cells_missing = ($cell_summaries | where {|s| not $s.manifest_found} | length)
    let cells_with_media = ($cells_found - $cells_without_media - $cells_missing)
    let all_items = ($cell_summaries | each {|s| $s.items} | flatten)
    let optimized_item_count = ($all_items | where {|r| $r.status? == "optimized"} | length)
    let failed_item_count = ($all_items | where {|r| $r.status? == "failed"} | length)

    {
        cells_found: $cells_found,
        cells_with_media: $cells_with_media,
        cells_without_media: $cells_without_media,
        cells_missing_manifest: $cells_missing,
        optimized_item_count: $optimized_item_count,
        failed_item_count: $failed_item_count,
        summary_path: $summary_path,
        archive_path: $archive_path,
        artifacts_tree: $artifacts_tree,
    }
}
