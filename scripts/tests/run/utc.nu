# Unit tests for scripts/lib/time/utc.nu utc-now.
# Run: nu scripts/tests/run/utc.nu

const SUITE_PATH = path self

use ../../lib/time/utc.nu [utc-now]
use ../../lib/tests/assert.nu *
use ../../lib/tests/runner.nu [run-suite]

def test-utc-now-is-string [] {
    test-log "\n[test-utc-now-is-string]"
    let t = (utc-now)
    [
        (assert-truthy (($t | describe) == "string") "utc-now returns a string")
    ]
}

def test-utc-now-format [] {
    test-log "\n[test-utc-now-format]"
    let t = (utc-now)
    let matches = ($t | parse --regex '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d+Z$')
    [
        (assert-truthy (not ($matches | is-empty)) "utc-now matches ISO 8601 with nanoseconds")
    ]
}

def test-utc-now-ends-with-z [] {
    test-log "\n[test-utc-now-ends-with-z]"
    let t = (utc-now)
    [
        (assert-truthy ($t | str ends-with "Z") "utc-now ends with Z (UTC)")
    ]
}

def test-utc-now-nanosecond-precision [] {
    test-log "\n[test-utc-now-nanosecond-precision]"
    let t = (utc-now)
    let decimal_part = ($t | split row "." | last | str replace "Z" "")
    [
        (assert-eq ($decimal_part | str length) 9 "decimal part is 9 digits (nanoseconds)")
    ]
}

def test-utc-now-monotonic [] {
    test-log "\n[test-utc-now-monotonic]"
    let t1 = (utc-now)
    sleep 2ms
    let t2 = (utc-now)
    [
        (assert-truthy ($t1 <= $t2) "consecutive calls are non-decreasing")
    ]
}

def main [] {
    test-log "=== run/utc-now tests ==="
    let results = (
        (test-utc-now-is-string)
        | append (test-utc-now-format)
        | append (test-utc-now-ends-with-z)
        | append (test-utc-now-nanosecond-precision)
        | append (test-utc-now-monotonic)
    ) | flatten
    run-suite "run/utc-now" $SUITE_PATH $results
}
