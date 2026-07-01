# Tuple identity fallback SSOT for artifact meta files.
#
# matrix_key coalesce: run.json > cell.json > result.v1.json
# flow_id derive: cell.flow_id > cell.scenario_module > matrix_key prefix > cell.scenario
# scenario_module: cell.scenario_module > derived flow_id

export def flow-id-from-matrix-key [matrix_key: string] {
    let trimmed = ($matrix_key | str trim)
    if ($trimmed | is-empty) { return "" }
    $trimmed | split row "__" | first
}

export def coalesce-matrix-key [cell: record, run: record, result: record] {
    let run_mk = ($run.matrix_key? | default "" | into string | str trim)
    let cell_mk = ($cell.matrix_key? | default "" | into string | str trim)
    let result_mk = ($result.matrix_key? | default "" | into string | str trim)
    if not ($run_mk | is-empty) {
        $run_mk
    } else if not ($cell_mk | is-empty) {
        $cell_mk
    } else {
        $result_mk
    }
}

def load-json-record [path: string] {
    if ($path | path exists) {
        try { open $path } catch { {} }
    } else {
        {}
    }
}

def load-cell-record [artifacts_base: string] {
    load-json-record ($artifacts_base | path join "meta" "cell.json")
}

def load-run-record [artifacts_base: string] {
    load-json-record ($artifacts_base | path join "meta" "run.json")
}

def load-result-record [artifacts_base: string] {
    load-json-record ($artifacts_base | path join "meta" "result.v1.json")
}

# Derive flow_id and scenario_module from cell fields plus coalesced matrix_key.
export def derive-tuple-identity [cell: record, matrix_key: string] {
    let cell_flow_id = ($cell.flow_id? | default "" | into string | str trim)
    let cell_scenario_mod = ($cell.scenario_module? | default "" | into string | str trim)
    let cell_legacy_scenario = ($cell.scenario? | default "" | into string | str trim)
    let coalesced_mk = ($matrix_key | default "" | into string | str trim)
    let derived_flow_id = if not ($cell_flow_id | is-empty) {
        $cell_flow_id
    } else if not ($cell_scenario_mod | is-empty) {
        $cell_scenario_mod
    } else {
        let from_matrix = (flow-id-from-matrix-key $coalesced_mk)
        if not ($from_matrix | is-empty) {
            $from_matrix
        } else if not ($cell_legacy_scenario | is-empty) {
            $cell_legacy_scenario
        } else {
            ""
        }
    }
    {
        matrix_key: $coalesced_mk,
        flow_id: $derived_flow_id,
        scenario_module: (
            if ($cell_scenario_mod | is-empty) { $derived_flow_id } else { $cell_scenario_mod }
        ),
    }
}

# Resolve matrix_key from artifact meta files. Explicit CLI value wins when set.
export def resolve-matrix-key [
    artifacts_base: string,
    --explicit: string = "",
] {
    if not ($explicit | is-empty) { return $explicit }
    let cell = (load-cell-record $artifacts_base)
    let run = (load-run-record $artifacts_base)
    let result = (load-result-record $artifacts_base)
    coalesce-matrix-key $cell $run $result
}

# Load identity fallbacks from meta/cell.json, meta/run.json, and meta/result.v1.json.
export def load-meta-identity [artifacts_base: string] {
    let cell = (load-cell-record $artifacts_base)
    let run = (load-run-record $artifacts_base)
    let result = (load-result-record $artifacts_base)
    let matrix_key = (coalesce-matrix-key $cell $run $result)
    let derived = (derive-tuple-identity $cell $matrix_key)
    $derived | merge {
        cell_id: ($cell.cell_id? | default ""),
        run_id: ($run.execution_id? | default ""),
    }
}
