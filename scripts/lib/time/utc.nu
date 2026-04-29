# UTC timestamp helpers.

# RFC-3339 UTC timestamp with nanosecond precision ("YYYY-MM-DDTHH:MM:SS.NNNNNNNNNZ").
export def now-utc [] {
    date now | date to-timezone "UTC" | format date "%Y-%m-%dT%H:%M:%S.%9fZ"
}
