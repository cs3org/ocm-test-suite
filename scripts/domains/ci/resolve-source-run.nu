# Resolve a workflow-dispatch artifact source run ID.
# If --run-id is non-empty, prints it directly without GH lookup.
# Otherwise queries GH for the latest successful run of --workflow on --branch.
# Fails non-zero if no successful run is found.

use ../../lib/ci/source-run.nu [resolve-source-run-id]

def main [
    --workflow: string = "", # Workflow filename, e.g. ci-matrix.yml
    --branch: string = "",   # Branch to search on
    --run-id: string = "",   # Pass-through an explicit run ID without GH lookup
] {
    if ($workflow | is-empty) {
        error make {msg: "resolve-source-run: --workflow is required"}
    }
    if ($branch | is-empty) {
        error make {msg: "resolve-source-run: --branch is required"}
    }

    print (resolve-source-run-id $run_id $workflow $branch)
}
