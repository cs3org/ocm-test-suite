# Resolve OCMTS repo root when the process PWD is not the repo.
#
# Resolution order: non-empty `OCMTS_ROOT`; else `git rev-parse
# --show-toplevel` when inside the repo; else error.
export def get-ocmts-root [] {
    let ocmts_root = ($env.OCMTS_ROOT? | default "")
    if not ($ocmts_root | is-empty) {
        return $ocmts_root
    }
    let result = (^git rev-parse --show-toplevel | complete)
    if $result.exit_code == 0 {
        return ($result.stdout | str trim)
    }
    error make {msg: "Cannot determine OCMTS root: not inside a git work tree and OCMTS_ROOT is not set"}
}
