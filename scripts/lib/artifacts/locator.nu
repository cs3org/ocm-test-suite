# Cell artifact directory locator.
# Re-exports execution-artifacts-path as cell-artifact-dir for discoverability.
# The canonical implementation lives in scripts/lib/run/execution-id.nu.

use ../run/execution-id.nu [execution-artifacts-path]

# Return the artifact directory path for a cell execution.
# Validates flow_id, pair, and execution_id shapes before building the path.
# Errors on invalid shapes (path traversal, bad format).
export def cell-artifact-dir [
    root: string,     # ocmts artifacts root (e.g. /path/to/artifacts)
    flow_id: string,
    pair: string,
    execution_id: string,
] {
    execution-artifacts-path $root $flow_id $pair $execution_id
}
