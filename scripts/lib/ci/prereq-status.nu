# Prerequisite status evaluation for CI run cells.
# Mirrors the bash "Check prerequisite status" step in ci-run-cell.yml.tpl.

# Evaluate prerequisite artifact directories and return the first failure reason.
# deps is a list of dependency cell-id strings. Empty strings in the list are
# skipped. prereqs_root is the directory containing per-dep subdirs.
# Each dep is expected to have a meta/result.v1.json somewhere under its
# subdir - the download layout nests execution directories above meta/, so
# we search recursively for the first match (sorted for determinism).
# Returns an empty string when all prerequisites passed (or deps is empty).
export def eval-prereq-status [
    deps: list<string>,
    prereqs_root: string,
]: nothing -> string {
    mut reason = ""
    for dep in $deps {
        let dep_trimmed = ($dep | str trim)
        if ($dep_trimmed | is-empty) { continue }
        let dep_dir = ($prereqs_root | path join $dep_trimmed)
        let matches = (
            glob $"($dep_dir)/**/meta/result.v1.json"
            | sort
        )
        if ($matches | is-empty) {
            $reason = $"prerequisite ($dep_trimmed) artifact missing or download failed"
            break
        }
        let result = (open ($matches | first))
        let status = ($result.status? | default "unknown")
        if $status != "passed" {
            $reason = $"prerequisite ($dep_trimmed) had status: ($status)"
            break
        }
    }
    $reason
}
