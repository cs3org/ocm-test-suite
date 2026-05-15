# Set up artifact directories for a test run.

use ../domain/core/ocmts-root.nu [get-ocmts-root]
use ../run/execution-id.nu [validate-pair validate-path-segment validate-execution-id]

# Create all subdirectories under artifacts/<flow_id>/<pair>/<execution_id>.
# Returns the artifacts base path.
export def init-artifact-dirs [flow_id: string, pair: string, execution_id: string] {
    let safe_flow = (validate-path-segment $flow_id "flow_id")
    let safe_pair = (validate-pair $pair)
    let safe_id = (validate-execution-id $execution_id)
    let root = get-ocmts-root
    let base = ($root | path join "artifacts" $safe_flow $safe_pair $safe_id)
    mkdir ($base | path join "compose")
    mkdir ($base | path join "cypress" "screenshots")
    mkdir ($base | path join "cypress" "videos")
    mkdir ($base | path join "cypress" "downloads")
    mkdir ($base | path join "docker" "logs")
    mkdir ($base | path join "meta")
    $base
}

# Write LAST_EXECUTION_ID marker under artifacts/<flow_id>/<pair>/.
export def write-last-execution-id [flow_id: string, pair: string, execution_id: string] {
    let safe_flow = (validate-path-segment $flow_id "flow_id")
    let safe_pair = (validate-pair $pair)
    let safe_id = (validate-execution-id $execution_id)
    let root = get-ocmts-root
    let dir = ($root | path join "artifacts" $safe_flow $safe_pair)
    mkdir $dir
    $safe_id | save --force ($dir | path join "LAST_EXECUTION_ID")
}

# Read LAST_EXECUTION_ID marker from artifacts/<flow_id>/<pair>/.
export def read-last-execution-id [flow_id: string, pair: string] {
    let safe_flow = (validate-path-segment $flow_id "flow_id")
    let safe_pair = (validate-pair $pair)
    let root = get-ocmts-root
    let marker = ($root | path join "artifacts" $safe_flow $safe_pair "LAST_EXECUTION_ID")
    if ($marker | path exists) {
        open --raw $marker | str trim
    } else {
        error make {msg: $"No last execution ID found for ($safe_flow)/($safe_pair). Pass --execution-id explicitly."}
    }
}
