# Find all suite execution directories under a root dir.
# Each execution dir contains meta/suite-manifest.v1.json.
# Prints one directory per line in lexicographic order.
# Output is suitable for piping into --dirs-file in aggregate commands.

def main [
    root_dir: string,   # Root directory to search under
] {
    let abs_root = ($root_dir | path expand)
    let dirs = (
        glob ($abs_root | path join "**" "meta" "suite-manifest.v1.json")
        | each {|f| $f | path dirname | path dirname}
        | sort
    )
    for dir in $dirs {
        print $dir
    }
}
