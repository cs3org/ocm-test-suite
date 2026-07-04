# Strict matrix cell expansion from a matrix-rules record.
# compute-cell failures propagate immediately; no catching or null suppression.

use ./cell.nu [compute-cell]
use ./expand.nu [expand-version-pairs]

# Build a flat cell list from a matrix-rules record.
# Merges enabled and mitm from the matrix config onto each cell.
export def expand-matrix-cells [rules: record] {
    $rules.matrix | items {|matrix_key, entry|
        let recv_platform = ($entry.receiver?.platform? | default "")
        let flow_id_arg = ($entry.flow_id? | default "")
        let version_pairs = (expand-version-pairs $entry)
        $version_pairs | each {|vp|
            $entry.browsers | each {|browser|
                let cell = (compute-cell
                    $flow_id_arg $entry.sender.platform $vp.sender_version $browser
                    $recv_platform $vp.receiver_version)
                $cell | merge {
                    enabled: ($entry.enabled? | default false),
                    mitm: ($entry.mitm? | default false),
                }
            }
        } | flatten
    } | flatten
}
