# Strict matrix cell expansion from a matrix-rules record.
# compute-cell failures propagate immediately; no catching or null suppression.

use ./cell.nu [compute-cell]
use ./expand.nu [expand-version-pairs]

# Build a flat cell list from a matrix-rules record.
# Merges enabled and mitm from the scenario config onto each cell.
# Fails hard if any compute-cell call raises an error.
export def expand-matrix-cells [rules: record] {
    $rules.scenarios | items {|scenario, sc|
        let recv_platform = ($sc.receiver?.platform? | default "")
        let flow_id_arg = ($sc.flow_id? | default $scenario)
        let version_pairs = (expand-version-pairs $sc)
        $version_pairs | each {|vp|
            $sc.browsers | each {|browser|
                let cell = (compute-cell
                    $scenario $sc.sender.platform $vp.sender_version $browser
                    $recv_platform $vp.receiver_version $flow_id_arg)
                $cell | merge {
                    enabled: ($sc.enabled? | default false),
                    mitm: ($sc.mitm? | default false),
                }
            }
        } | flatten
    } | flatten
}
