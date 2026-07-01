# Internal helpers shared across lib/site/ split files.
# Not part of any external API; do not import from outside lib/site/.

use ../matrix/cell.nu [compute-cell]
use ../matrix/expand.nu [expand-version-pairs]

# True when a relative artifact path falls inside the publish allowlist.
export def evidence-path-allowed [rel: string] {
    (($rel | str starts-with "meta/")
        or ($rel | str starts-with "docker/logs/")
        or ($rel | str starts-with "cypress/videos/")
        or ($rel | str starts-with "cypress/screenshots/")
        or ($rel == "mitm/peers.json")
        or ($rel | str starts-with "mitm/flows/")
        or ($rel == "mitm/redaction-report.json")
        or ($rel | str starts-with "mitm/reports/")
        or ($rel | str starts-with "compose/"))
}

# Build a flat cell list from the in-memory matrix rules record.
# Mirrors `matrix list --json`: one row per
# (flow, sender_version, receiver_version, browser) for two-party,
# or (flow, sender_version, browser) for one-party. Includes disabled
# flows (placeholder universe). Does NOT call assert-matrix-entry-enabled.
#
# Best-effort: each compute-cell call is wrapped in try/catch. On failure
# the row is warned to stderr and dropped. This differs from
# expand-matrix-cells (matrix/cells.nu) which fails hard on any cell error.
# Site ingest favors a partial result over a complete abort.
export def compute-matrix-cells [rules: record] {
    $rules.matrix | items {|_matrix_key, entry|
        let recv_platform = ($entry.receiver?.platform? | default "")
        let flow_id_arg = ($entry.flow_id? | default "")
        let version_pairs = (expand-version-pairs $entry)
        $version_pairs | each {|vp|
            $entry.browsers | each {|browser|
                let cell = (try {
                    (compute-cell $flow_id_arg $entry.sender.platform $vp.sender_version $browser
                        $recv_platform $vp.receiver_version)
                } catch {|e|
                    print --stderr $"WARNING: compute-cell failed for ($flow_id_arg)/($vp.sender_version)/($browser): ($e.msg)"
                    null
                })
                if $cell != null {
                    $cell | merge {
                        enabled: ($entry.enabled? | default false),
                        mitm: ($entry.mitm? | default false),
                    }
                }
            } | where {|x| $x != null}
        } | flatten
    } | flatten
}
