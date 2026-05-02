# UTC timestamp helpers.

# RFC-3339 UTC timestamp with nanosecond precision ("YYYY-MM-DDTHH:MM:SS.NNNNNNNNNZ").
# Canonical name and precision for all UTC timestamps in this codebase.
export def utc-now [] {
    date now | date to-timezone "UTC" | format date "%Y-%m-%dT%H:%M:%S.%9fZ"
}
