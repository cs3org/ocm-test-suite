# Vendored from MAIDE (scripts/lib/common/complete-record.nu) for ocmts independence.
# Do not import or symlink across repos. If MAIDE updates this file, port the
# changes here by hand.

# Generic helpers for the `complete` record produced by `| complete` on external commands.
# Fields: exit_code int, stdout string, stderr string.
# Returns true when the command exited successfully.
export def complete-ok []: record -> bool {
    $in.exit_code == 0
}

# Returns trimmed stdout.
# Fails with message and stderr content when exit_code != 0.
export def complete-stdout []: record -> string {
    let r = $in
    if $r.exit_code != 0 {
        error make {
            msg: $"command failed (exit ($r.exit_code)): ($r.stderr | str trim)"
        }
    }
    $r.stdout | str trim
}

# If exit_code != 0, print msg and stderr to stderr then exit 2.
# Does nothing on success.
export def complete-or-fail [msg: string]: record -> nothing {
    let r = $in
    if $r.exit_code != 0 {
        print --stderr $"($msg)\n($r.stderr | str trim)"
        exit 2
    }
}
