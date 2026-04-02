# Shared compose file list helpers.

# Build the -f args list from an ordered file list.
export def build-f-args [files: list<string>] {
    $files | each {|f| ["-f" $f]} | flatten
}

# Persist the active compose file set to compose/active-files.txt.
export def write-active-files [
    artifacts_base: string,
    base_yml: string,
    base_overlay_fnames: list<string>,
    runner_fname: string = "",
] {
    let art_inputs = ($artifacts_base | path join "compose" "inputs")
    let base_files = ([$base_yml] | append (
        $base_overlay_fnames | each {|f| $art_inputs | path join $f}
    ))
    let active_files = if ($runner_fname | is-empty) {
        $base_files
    } else {
        $base_files | append ($art_inputs | path join $runner_fname)
    }
    $active_files | str join "\n"
    | save --force ($artifacts_base | path join "compose" "active-files.txt")
}

# Read active compose file list from active-files.txt if present,
# falling back to the legacy base-only list.
export def read-active-compose-files [
    artifacts_base: string,
    base_yml: string,
] {
    let active_files_path = ($artifacts_base | path join "compose" "active-files.txt")
    if ($active_files_path | path exists) {
        open --raw $active_files_path | lines | where {|l| not ($l | is-empty)}
    } else {
        let art_inputs = ($artifacts_base | path join "compose" "inputs")
        [
            $base_yml
            ($art_inputs | path join "exec.yml")
            ($art_inputs | path join "platform.yml")
            ($art_inputs | path join "helpers.yml")
        ]
    }
}

# Build the runner-ci file set: base active files + runner-ci.yml.
# Always appends runner-ci.yml (preserves existing test-run behavior).
export def build-run-files [
    artifacts_base: string,
    base_yml: string,
] {
    let inputs = ($artifacts_base | path join "compose" "inputs")
    let base_set = (read-active-compose-files $artifacts_base $base_yml)
    $base_set | append ($inputs | path join "runner-ci.yml")
}

# Return the stack.env path from compose inputs if it exists; empty string otherwise.
export def read-compose-env-file [artifacts_base: string] {
    let p = ($artifacts_base | path join "compose" "inputs" "stack.env")
    if ($p | path exists) { $p } else { "" }
}
