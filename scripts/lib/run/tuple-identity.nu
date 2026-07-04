# Tuple identity SSOT for artifact meta files.
#
# matrix_key: explicit CLI value > meta/run.json (prepared-run inheritance).
# flow_id: meta/cell.json only; error when absent (no reconstruction).

def open-json-record [path: string, label: string] {
    try {
        open $path
    } catch {|e|
        error make {
            msg: $"($label) at ($path) is malformed or unreadable: ($e.msg)"
        }
    }
}

def load-cell-record [artifacts_base: string] {
    let path = ($artifacts_base | path join "meta" "cell.json")
    if not ($path | path exists) {
        return {}
    }
    open-json-record $path "meta/cell.json"
}

# Missing meta/run.json is allowed; malformed content is not.
def load-run-record-optional [artifacts_base: string] {
    let path = ($artifacts_base | path join "meta" "run.json")
    if not ($path | path exists) {
        return {}
    }
    open-json-record $path "meta/run.json"
}

def matrix-key-from-run [run: record] {
    ($run.matrix_key? | default "" | into string | str trim)
}

# Resolve matrix_key for terminal writers. Explicit CLI value wins when set.
export def resolve-matrix-key [
    artifacts_base: string,
    --explicit: string = "",
] {
    if not ($explicit | is-empty) { return $explicit }
    let run = (load-run-record-optional $artifacts_base)
    matrix-key-from-run $run
}

# Strict tuple identity from cell.json plus run.json matrix_key inheritance.
export def load-meta-identity [artifacts_base: string] {
    let cell = (load-cell-record $artifacts_base)
    let run = (load-run-record-optional $artifacts_base)
    let matrix_key = (matrix-key-from-run $run)
    let flow_id = ($cell.flow_id? | default "" | into string | str trim)
    if ($flow_id | is-empty) {
        error make {
            msg: $"meta/cell.json in ($artifacts_base) is missing canonical flow_id."
        }
    }
    {
        matrix_key: $matrix_key,
        flow_id: $flow_id,
        cell_id: ($cell.cell_id? | default "" | into string | str trim),
        run_id: ($run.execution_id? | default "" | into string | str trim),
    }
}
