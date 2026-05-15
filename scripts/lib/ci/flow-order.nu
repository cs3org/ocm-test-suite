# Shared flow-order helper used by CI workflow generation and local suite runs.
# Single source of truth for the cell ordering contract defined in
# config/ci/workflows.nuon github.job_order.

# Sort plan cells by visual flow order from config.
# Cells with a flow_id matching job_order appear first, in order.
# Cells with unlisted flow_ids appear last, stable within each group.
export def sort-cells-by-flow-order [
    cells: list,
    job_order: list<string>,
]: any -> list {
    let flow_to_pos = ($job_order | enumerate | reduce --fold {} {|e, acc|
        $acc | insert $e.item $e.index
    })
    let snap = $flow_to_pos
    $cells | sort-by {|c|
        let pos = ($snap | get --optional $c.flow_id | default 9999)
        [$pos $c.cell_id]
    }
}
