# Vendored from MAIDE (scripts/lib/common/stderr-match.nu) for ocmts independence.
# Case-insensitive matching helpers for stderr strings.
# Do not import or symlink across repos. If MAIDE updates this file, port the
# changes here by hand.

# Helpers for substring checks on stderr strings.
# Matching is case-insensitive for every helper below.

# True if stderr contains `pattern` as a substring (case-insensitive).
export def stderr-contains [stderr: string, pattern: string]: nothing -> bool {
    ($stderr | str downcase) | str contains ($pattern | str downcase)
}

# True if stderr contains any listed pattern (case-insensitive).
export def stderr-matches-any [stderr: string, patterns: list<string>]: nothing -> bool {
    $patterns | any {|p| stderr-contains $stderr $p}
}

# First pattern that appears in stderr, or null when none match.
export def stderr-first-match [stderr: string, patterns: list<string>]: nothing -> any {
    let matches = ($patterns | where {|p| stderr-contains $stderr $p})
    if ($matches | is-empty) { null } else { $matches | first }
}
