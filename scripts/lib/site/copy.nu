# Artifact copy with an allowlist predicate.

use ./internal.nu [evidence-path-allowed]

# Copy allowlisted artifact files from src_dir into dst_dir.
# Returns the number of files copied.
export def copy-allowlisted-artifacts [src_dir: string, dst_dir: string] {
    let src = ($src_dir | path expand)
    let all_files = (try {
        glob $"($src)/**/*"
        | where {|p| ($p | path type) == "file"}
    } catch { [] })
    let allowed = ($all_files | where {|p|
        let rel = ($p | path relative-to $src)
        evidence-path-allowed $rel
    })
    for f in $allowed {
        let rel = ($f | path relative-to $src)
        let dst = ($dst_dir | path join $rel)
        mkdir ($dst | path dirname)
        cp $f $dst
    }
    ($allowed | length)
}
