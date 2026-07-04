# Aggregate downloaded optimized-media cell artifact directories into one bundle.
# Reads per-cell manifests, validates paths, merges derived media into an
# artifacts/ tree, and emits:
#   optimized-media-artifacts.tar.zst  (archive of the merged artifacts tree)
#   meta/optimized-media-summary.v1.json

use ../../lib/artifacts/aggregate-optimized-media.nu [aggregate-optimized-media-cells]
use ../../lib/site/config.nu [resolve-zstd-archive-policy]

def main [
    ...artifact_dirs: string,
    --dirs-file: string = "",   # file with one artifact dir path per line
    --scan-dir: string = "",    # scan immediate child dirs of this root dir
    --output-dir: string = "",  # destination directory (required)
    --no-archive,               # skip creating optimized-media-artifacts.tar.zst
] {
    if ($output_dir | is-empty) {
        error make {msg: "aggregate-optimized-media: --output-dir is required"}
    }

    let dirs = if not ($dirs_file | is-empty) {
        open --raw $dirs_file
        | lines
        | where {|l| not ($l | str trim | is-empty)}
        | each {|l| $l | str trim}
    } else if not ($scan_dir | is-empty) {
        if not ($scan_dir | path exists) {
            error make {msg: $"aggregate-optimized-media: --scan-dir path does not exist: ($scan_dir)"}
        }
        ls $scan_dir
        | where type == "dir"
        | get name
        | sort
    } else {
        $artifact_dirs
    }

    if ($dirs | is-empty) {
        if not ($scan_dir | is-empty) {
            error make {msg: $"aggregate-optimized-media: --scan-dir found no child directories under: ($scan_dir)"}
        }
        error make {msg: "aggregate-optimized-media: no artifact directories provided. Use positional args, --dirs-file, or --scan-dir"}
    }

    let dir_count = ($dirs | length)
    print $"Aggregating ($dir_count) optimized-media cell artifact dirs into ($output_dir)"

    let result = if $no_archive {
        aggregate-optimized-media-cells $dirs $output_dir --no-archive
    } else {
        let zstd_policy = (resolve-zstd-archive-policy)
        aggregate-optimized-media-cells $dirs $output_dir --zstd-policy $zstd_policy
    }

    print $"  cells found:            ($result.cells_found)"
    print $"  cells with media:       ($result.cells_with_media)"
    print $"  cells without media:    ($result.cells_without_media)"
    print $"  cells missing manifest: ($result.cells_missing_manifest)"
    print $"  optimized items:        ($result.optimized_item_count)"
    print $"  failed items:           ($result.failed_item_count)"
    print $"  summary manifest:       ($result.summary_path)"
    if $result.archive_path != null {
        print $"  archive:                ($result.archive_path)"
    }

    if $result.cells_missing_manifest > 0 {
        let n = $result.cells_missing_manifest
        print $"  WARNING: ($n) cells had no manifest - check pipeline wiring"
    }
    if $result.failed_item_count > 0 {
        let n = $result.failed_item_count
        print $"  FAILED: ($n) items failed to optimize"
        error make {msg: $"aggregate-optimized-media: ($n) item\(s\) failed to optimize"}
    }
}
