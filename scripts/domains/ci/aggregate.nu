# Aggregate per-cell artifact directories into one suite manifest.
# artifact_dirs is a newline-separated list of paths read from --dirs-file,
# or can be passed directly as positional args.
# --expected-cells: comma-separated cell_ids planned for this suite (enables
#   missing-cell detection; cells with no manifest get a "missing" result).
# --archive: create a zstd tar archive of the artifacts tree after aggregation.

use ../../lib/ci/aggregate.nu [write-aggregated-suite-manifest create-suite-archive reconstruct-suite-index]
use ../../lib/domain/core/ocmts-root.nu [get-ocmts-root]

def main [
    ...artifact_dirs: string,
    --dirs-file: string = "",       # Read per-cell artifact dirs from this file
    --suite-id: string = "",        # Suite ID to stamp on the output
    --output-dir: string = "",      # Write aggregated manifest here
    --expected-cells: string = "",  # Comma-separated planned cell_ids for completeness check
    --archive,                      # Create suite-artifacts.tar.zst after aggregation
] {
    let root = get-ocmts-root
    let dirs = if not ($dirs_file | is-empty) {
        open --raw $dirs_file | lines | where {|l| not ($l | is-empty)} | each {|l| $l | str trim}
    } else {
        $artifact_dirs
    }
    if ($dirs | is-empty) {
        error make {msg: "aggregate: no artifact directories provided. Use positional args or --dirs-file"}
    }
    let eff_id = if ($suite_id | is-empty) { "unknown-suite" } else { $suite_id }
    let out_dir = if ($output_dir | is-empty) {
        $root | path join "artifacts/suites/aggregated"
    } else {
        $output_dir
    }
    let expected_ids = if ($expected_cells | is-empty) {
        []
    } else {
        $expected_cells | split row "," | each {|s| $s | str trim} | where {|s| not ($s | is-empty)}
    }
    let path = (write-aggregated-suite-manifest $dirs $eff_id $out_dir
        --expected-cell-ids $expected_ids)
    print $"Aggregated suite manifest written to ($path)"

    let artifacts_root = ($root | path join "artifacts")

    # Reconstruct suite index so downstream suite-based consumers can find
    # all runs (including blocked/missing) via artifacts/suites/.
    let manifest = (open $path)
    let suite_record_path = (reconstruct-suite-index $manifest $artifacts_root)
    if $suite_record_path != null {
        print $"Suite index written to ($suite_record_path)"
    } else {
        print "Suite index reconstruction skipped: suite_id not in expected format"
    }

    if $archive {
        let archive_path = (create-suite-archive $artifacts_root $out_dir)
        print $"Suite archive created: ($archive_path)"
    }
}
