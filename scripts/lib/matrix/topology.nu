# Single source of truth for flow topology (one-party vs two-party).
# The canonical declaration lives in config/matrix/flows/<flow_id>.nuon
# under the top-level `two_party: bool` field. All runtime derivations
# of "is this a two-party run?" must cross-check against this helper.

use ../domain/core/ocmts-root.nu [get-ocmts-root]

# Read the canonical two_party value for a flow from config/matrix/flows/.
# Errors if the file is missing or the field is absent or not a bool.
export def flow-is-two-party [flow_id: string]: nothing -> bool {
    let root = get-ocmts-root
    let flow_path = ($root | path join $"config/matrix/flows/($flow_id).nuon")
    if not ($flow_path | path exists) {
        error make {msg: $"Flow file not found: config/matrix/flows/($flow_id).nuon"}
    }
    let flow = (open $flow_path)
    let val = ($flow.two_party?)
    if $val == null {
        error make {msg: $"Flow file '($flow_id).nuon' is missing the 'two_party: bool' field"}
    }
    if ($val | describe) != "bool" {
        error make {msg: $"Flow file '($flow_id).nuon' is missing the 'two_party: bool' field"}
    }
    $val
}

# Two-party flows require --receiver-platform; one-party flows reject it early.
export def require-receiver-platform-for-two-party [
    flow_id: string,
    receiver_platform: string = "",
] {
    let canonical_two_party = (flow-is-two-party $flow_id)
    if $canonical_two_party and ($receiver_platform | is-empty) {
        error make {
            msg: $"Flow '($flow_id)' requires --receiver-platform for two-party flows"
        }
    }
    if (not $canonical_two_party) and (not ($receiver_platform | is-empty)) {
        error make {
            msg: $"Flow '($flow_id)' is one-party; do not pass --receiver-platform"
        }
    }
    $canonical_two_party
}

# One-party flows must not carry a receiver version flag.
export def reject-spurious-receiver-version-for-one-party [
    flow_id: string,
    receiver_version: string = "",
] {
    if (not (flow-is-two-party $flow_id)) and (not ($receiver_version | is-empty)) {
        error make {
            msg: $"Flow '($flow_id)' is one-party; do not pass --receiver-version"
        }
    }
}

# Assert that derived_two_party matches the canonical two_party for flow_id.
# source names the caller context for a readable error (e.g. "compute-cell args").
# Errors with a clear mismatch message; returns nothing on match.
export def assert-topology-matches [
    flow_id: string,
    derived_two_party: bool,
    source: string,
]: nothing -> nothing {
    let canonical = (flow-is-two-party $flow_id)
    if $derived_two_party != $canonical {
        error make {msg: $"Topology mismatch for flow '($flow_id)': flow file declares two_party=($canonical) but ($source) derived two_party=($derived_two_party). Fix the inconsistent input."}
    }
}
