# Shared compose file list helpers.

use ../time/utc.nu [utc-now]
use ../schema/validate.nu [assert-schema-version]

# Build the -f args list from an ordered file list.
export def build-f-args [files: list<string>] {
    $files | each {|f| ["-f" $f]} | flatten
}

# Return the stack.env path from compose inputs if it exists; empty string otherwise.
export def read-compose-env-file [artifacts_base: string] {
    let p = ($artifacts_base | path join "compose" "inputs" "stack.env")
    if ($p | path exists) { $p } else { "" }
}

# Write compose/manifest.v1.json with overlay sha256 hashes and applied input list.
export def write-compose-manifest [
    artifacts_base: string,
    stack_id: string,
    base_overlay_fnames: list<string>,
    runner_fname: string = "",
    resolved_files: list<string> = [],
] {
    let art_inputs = ($artifacts_base | path join "compose" "inputs")

    let overlay_paths = ($base_overlay_fnames | each {|f| $art_inputs | path join $f})
    let runner_paths = if ($runner_fname | is-not-empty) {
        [($art_inputs | path join $runner_fname)]
    } else {
        []
    }
    let all_overlay_paths = ($overlay_paths | append $runner_paths | sort)
    let combined = ($all_overlay_paths | each {|f| open --raw $f} | str join "")
    let stack_def_sha256 = ($combined | hash sha256)

    let stack_env_path = ($art_inputs | path join "stack.env")
    let stack_env_sha256 = if ($stack_env_path | path exists) {
        open --raw $stack_env_path | hash sha256
    } else {
        ""
    }

    let runner_input = if ($runner_fname | is-not-empty) { [$"inputs/($runner_fname)"] } else { [] }
    let applied_inputs = (
        ["config/compose/base.yml"]
        | append ($base_overlay_fnames | each {|f| $"inputs/($f)"})
        | append $runner_input
    )

    let manifest = {
        schema_version: 1,
        captured_at: (utc-now),
        stack_id: $stack_id,
        stack_def_sha256: $stack_def_sha256,
        stack_env_sha256: $stack_env_sha256,
        base: "config/compose/base.yml",
        applied_inputs: $applied_inputs,
        resolved_files: $resolved_files,
    }
    $manifest | to json --indent 2
    | save --force ($artifacts_base | path join "compose" "manifest.v1.json")
}

# Read compose/manifest.v1.json from artifacts_base; errors if absent.
export def read-compose-manifest [artifacts_base: string] {
    let p = ($artifacts_base | path join "compose" "manifest.v1.json")
    if not ($p | path exists) {
        error make {msg: $"No compose/manifest.v1.json found at ($p)"}
    }
    let doc = (open $p)
    assert-schema-version $doc 1 $p
    $doc
}

# Return the stack_id field from compose/manifest.v1.json.
# Currently no Nushell callers (operator-side reads stack_id from
# meta/run.json.stack_id). Kept as a public helper because
# compose/manifest.v1.json.stack_id is the data-shape contract used
# by the Observatory UI; both files are written from the same
# in-memory value and always agree.
export def read-stack-id-from-manifest [artifacts_base: string] {
    let m = (read-compose-manifest $artifacts_base)
    $m.stack_id
}

# Return absolute compose file paths for a docker compose -f invocation.
# First entry is the repo base.yml; subsequent entries resolve relative
# to <artifacts_base>/compose/.
export def read-compose-files-from-manifest [
    artifacts_base: string,
    root: string,
] {
    let m = (read-compose-manifest $artifacts_base)
    let inputs = ($m.applied_inputs | default [])
    let base_abs = ($root | path join $m.base)
    let rest = ($inputs | skip 1 | each {|rel|
        ($artifacts_base | path join "compose" $rel)
    })
    [$base_abs] | append $rest
}
