# Returns the tail cells to mark skipped when stop-on-fail fires.
# The current failed cell is identified by cell_id; every later planned cell becomes skipped.

export def stop-on-fail-tail [cells: list, current_cell_id: string] {
    let result = ($cells | reduce --fold {found_current: false, tail: []} {|candidate, acc|
        if $acc.found_current {
            $acc | update tail {|state| $state.tail | append $candidate}
        } else if $candidate.cell_id == $current_cell_id {
            $acc | update found_current true
        } else {
            $acc
        }
    })
    if not $result.found_current {
        error make {msg: $"stop-on-fail current cell not found in plan: ($current_cell_id)"}
    }
    $result.tail
}
