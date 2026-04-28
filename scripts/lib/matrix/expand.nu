# Version-pair expansion helpers for matrix scenario cells.
# Reused by matrix list, site-ingest, and test suite expansion.

# Expand (sender_version, receiver_version) pairs for a scenario record
# from the in-memory matrix rules, honoring version_pairing policy.
#
# For cross_product (default): cartesian product of sender.version_lines x
# receiver.version_lines. When receiver is null, receiver_version is "".
# For explicit_pairs: use sc.version_pairs (each entry has sender and receiver).
#
# Returns list<record<sender_version: string, receiver_version: string>>.
export def expand-version-pairs [sc: record] {
    let pairing = ($sc.version_pairing? | default "cross_product")
    match $pairing {
        "cross_product" => {
            let recv_vl = if ($sc.receiver? != null) {
                $sc.receiver.version_lines
            } else {
                [""]
            }
            $recv_vl | each {|rv|
                $sc.sender.version_lines | each {|sv|
                    {sender_version: $sv, receiver_version: $rv}
                }
            } | flatten
        }
        "explicit_pairs" => {
            let pairs = ($sc.version_pairs? | default [])
            $pairs | each {|p| {sender_version: $p.sender, receiver_version: $p.receiver}}
        }
        _ => {
            error make {msg: $"Unknown version_pairing '($pairing)'. Expected: cross_product or explicit_pairs"}
        }
    }
}
