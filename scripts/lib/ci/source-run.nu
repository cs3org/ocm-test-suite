# Source-run ID resolution helpers.
# Encapsulates the workflow-dispatch source run lookup used by ci-site.

# Return run_id unchanged if non-empty; otherwise query GH for the latest
# successful run of workflow on branch. Fails non-zero if none found.
export def resolve-source-run-id [
    run_id: string,   # explicit passthrough; empty string triggers GH lookup
    workflow: string, # workflow filename, e.g. ci-matrix.yml
    branch: string,   # branch to search on
]: nothing -> string {
    if not ($run_id | is-empty) {
        return $run_id
    }

    let result = (^gh run list
        --workflow $workflow
        --branch $branch
        --status success
        --limit 1
        --json databaseId
        --jq '.[0].databaseId // ""'
        | complete)

    if $result.exit_code != 0 {
        error make {msg: $"resolve-source-run-id: gh run list failed: ($result.stderr | str trim)"}
    }

    let found = ($result.stdout | str trim)
    if ($found | is-empty) {
        error make {msg: $"resolve-source-run-id: no successful ($workflow) run found on ($branch)"}
    }

    $found
}
