# Generate a unique execution_id based on timestamp and a random suffix.

export def new-execution-id [] {
    let ts = (date now | format date "%Y%m%dt%H%M%S")
    let rand = (random uuid | split row '-' | first)
    $"($ts)-($rand)"
}

# Validate execution_id shape: YYYYMMDDtHHMMSS-<8 hex chars>.
# Rejects path traversal patterns and non-conformant shapes so callers
# fail before unsafe path/rm use. Returns the validated id for binding.
export def validate-execution-id [execution_id: string] {
    if ($execution_id | str contains "..") {
        error make {msg: $"execution_id path traversal rejected: ($execution_id)"}
    }
    if not ($execution_id =~ '^\d{8}t\d{6}-[0-9a-f]{8}$') {
        error make {msg: $"execution_id shape invalid: ($execution_id)"}
    }
    $execution_id
}

# Validate a single path segment used in artifact directories: lowercase
# alphanumeric groups separated by single hyphens only. Accepts "nextcloud",
# "v33", "login"; rejects dots, spaces, slashes, traversal, consecutive
# hyphens, and leading/trailing hyphens. label names the segment in errors.
export def validate-path-segment [segment: string, label: string] {
    if ($segment | is-empty) {
        error make {msg: $"($label) must not be empty"}
    }
    if ($segment | str contains "/") {
        error make {msg: $"($label) contains slash: ($segment)"}
    }
    if not ($segment =~ '^[a-z0-9]+(-[a-z0-9]+)*$') {
        error make {msg: $"($label) shape invalid - expected lowercase slug \(alnum+hyphens\): ($segment)"}
    }
    $segment
}

# Validate an artifact name: lowercase alphanumeric groups separated by single
# hyphens only. Accepts cell-login-nextcloud-v33; rejects dots, spaces, slashes,
# consecutive hyphens, and leading/trailing hyphens.
export def validate-artifact-name [artifact_name: string] {
    validate-path-segment $artifact_name "artifact_name"
}

# Validate a pair segment: opaque role-ordered slug, no slashes or traversal.
# Accepts "nextcloud-v33" (1p) or "nextcloud-v33-nextcloud-v33" (2p).
export def validate-pair [pair: string] {
    validate-path-segment $pair "pair"
}

# Construct the artifact run path for an execution using the new path contract:
#   artifacts/<flow_id>/<pair>/<execution_id>
# Validates all three locator fields before any path use.
export def execution-artifacts-path [
    root: string,
    flow_id: string,
    pair: string,
    execution_id: string,
] {
    let safe_flow = (validate-path-segment $flow_id "flow_id")
    let safe_pair = (validate-pair $pair)
    let safe_id = (validate-execution-id $execution_id)
    $root | path join "artifacts" $safe_flow $safe_pair $safe_id
}

# Construct the temp run path for an execution, validating id first.
# Rejects path traversal and invalid shapes before any /tmp use.
export def execution-temp-path [execution_id: string] {
    let safe_id = (validate-execution-id $execution_id)
    $"/tmp/ocmts/($safe_id)"
}
