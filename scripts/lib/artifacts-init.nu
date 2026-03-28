# Set up artifact directories for a test run.

use ./domain/core/ocmts-root.nu [get-ocmts-root]
use ./execution-id.nu [validate-artifact-name validate-execution-id]

export def init-artifact-dirs [artifact_name: string, execution_id: string] {
    let safe_name = (validate-artifact-name $artifact_name)
    let safe_id = (validate-execution-id $execution_id)
    let root = get-ocmts-root
    let base = ($root | path join "artifacts" $safe_name $safe_id)
    mkdir ($base | path join "compose")
    mkdir ($base | path join "cypress" "screenshots")
    mkdir ($base | path join "cypress" "videos")
    mkdir ($base | path join "cypress" "downloads")
    mkdir ($base | path join "docker" "logs")
    mkdir ($base | path join "meta")
    $base
}

export def write-last-execution-id [artifact_name: string, execution_id: string] {
    let safe_name = (validate-artifact-name $artifact_name)
    let safe_id = (validate-execution-id $execution_id)
    let root = get-ocmts-root
    let dir = ($root | path join "artifacts" $safe_name)
    mkdir $dir
    $safe_id | save --force ($dir | path join "LAST_EXECUTION_ID")
}

export def read-last-execution-id [artifact_name: string] {
    let safe_name = (validate-artifact-name $artifact_name)
    let root = get-ocmts-root
    let marker = ($root | path join "artifacts" $safe_name "LAST_EXECUTION_ID")
    if ($marker | path exists) {
        open --raw $marker | str trim
    } else {
        error make {msg: $"No last execution ID found for ($artifact_name). Pass --execution-id explicitly."}
    }
}
