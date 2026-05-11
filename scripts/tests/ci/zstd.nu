# Unit tests for build-zstd-flags and default_zstd_archive_policy.
# Run: nu scripts/tests/ci/zstd.nu
# Returns exit 0 on all pass, exit 1 with details on failure.

const SUITE_PATH = path self

use ../../lib/ci/zstd.nu [build-zstd-flags default_zstd_archive_policy]
use ../../lib/tests/assert.nu *
use ../../lib/tests/runner.nu [run-suite]

# default_zstd_archive_policy has expected CI-appropriate fields.
def test-default-policy-shape [] {
    test-log "\n[test-default-policy-shape]"
    [
        (assert-not-null ($default_zstd_archive_policy.level?) "level present")
        (assert-not-null ($default_zstd_archive_policy.threads?) "threads present")
        (assert-not-null ($default_zstd_archive_policy.checksum?) "checksum present")
    ]
}

# default_zstd_archive_policy has expected CI default values.
def test-default-policy-values [] {
    test-log "\n[test-default-policy-values]"
    [
        (assert-eq $default_zstd_archive_policy.level 3 "level is 3 (zstd default, CI-appropriate)")
        (assert-eq $default_zstd_archive_policy.threads 0 "threads is 0 (auto-detect)")
        (assert-eq $default_zstd_archive_policy.checksum true "checksum is true")
    ]
}

# build-zstd-flags with checksum:true produces -<level>, -T<threads>, --check.
def test-build-flags-with-checksum [] {
    test-log "\n[test-build-flags-with-checksum]"
    let policy = {level: 3, threads: 0, checksum: true}
    let flags = (build-zstd-flags $policy)
    [
        (assert-eq ($flags | length) 3 "three flags when checksum enabled")
        (assert-eq ($flags | get 0) "-3" "first flag is -3 (level)")
        (assert-eq ($flags | get 1) "-T0" "second flag is -T0 (threads auto)")
        (assert-eq ($flags | get 2) "--check" "third flag is --check")
    ]
}

# build-zstd-flags with checksum:false omits --check.
def test-build-flags-no-checksum [] {
    test-log "\n[test-build-flags-no-checksum]"
    let policy = {level: 3, threads: 0, checksum: false}
    let flags = (build-zstd-flags $policy)
    [
        (assert-eq ($flags | length) 2 "two flags when checksum disabled")
        (assert-truthy (not ("--check" in $flags)) "--check absent when checksum false")
    ]
}

# build-zstd-flags honors custom level.
def test-build-flags-custom-level [] {
    test-log "\n[test-build-flags-custom-level]"
    let policy = {level: 9, threads: 4, checksum: false}
    let flags = (build-zstd-flags $policy)
    [
        (assert-eq ($flags | get 0) "-9" "level 9 produces -9")
        (assert-eq ($flags | get 1) "-T4" "threads 4 produces -T4")
    ]
}

# build-zstd-flags: default policy produces the expected flag set end-to-end.
def test-build-flags-default-policy [] {
    test-log "\n[test-build-flags-default-policy]"
    let flags = (build-zstd-flags $default_zstd_archive_policy)
    [
        (assert-truthy ("-3" in $flags) "-3 present for default level")
        (assert-truthy ("-T0" in $flags) "-T0 present for default threads")
        (assert-truthy ("--check" in $flags) "--check present for default checksum")
    ]
}

def main [] {
    test-log "=== CI Zstd Policy Tests ==="
    let results = (
        (test-default-policy-shape)
        | append (test-default-policy-values)
        | append (test-build-flags-with-checksum)
        | append (test-build-flags-no-checksum)
        | append (test-build-flags-custom-level)
        | append (test-build-flags-default-policy)
    ) | flatten
    run-suite "ci/zstd" $SUITE_PATH $results
}
