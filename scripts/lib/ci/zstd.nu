# Shared zstd helpers for CI artifact archive creation.
# Consumed by ci/aggregate.nu and artifacts/aggregate-optimized-media.nu.

# Default zstd archive policy tuned for GitHub CI artifact archives.
# level 3: zstd default; good compression-speed balance for CI upload.
# threads 0: auto-detect (all available CPUs on the runner).
# checksum true: add an integrity checksum (--check flag).
export const default_zstd_archive_policy = {
    level: 3,
    threads: 0,
    checksum: true,
}

# Build the zstd flag list from an archive policy record.
# Returns a list<string> ready for splatting into a ^zstd call.
# Callers prepend -f and append -o <path> around the splat.
export def build-zstd-flags [policy: record]: nothing -> list<string> {
    let level_flag = $"-($policy.level)"
    let thread_flag = $"-T($policy.threads)"
    [$level_flag $thread_flag] | append (if $policy.checksum { ["--check"] } else { [] })
}
