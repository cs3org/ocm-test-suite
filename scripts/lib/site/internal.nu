# Internal helpers shared across lib/site/ split files.
# Not part of any external API; do not import from outside lib/site/.

use ../matrix/cell.nu [compute-cell]
use ../matrix/expand.nu [expand-version-pairs]

# RFC-3339 UTC timestamp ("YYYY-MM-DDTHH:MM:SSZ").
export def now-utc [] {
    date now | date to-timezone "UTC" | format date "%Y-%m-%dT%H:%M:%SZ"
}

# True when a relative artifact path falls inside the publish allowlist.
export def evidence-path-allowed [rel: string] {
    (($rel | str starts-with "meta/")
        or ($rel | str starts-with "docker/logs/")
        or ($rel | str starts-with "cypress/videos/")
        or ($rel | str starts-with "cypress/screenshots/")
        or ($rel == "mitm/peers.json")
        or ($rel | str starts-with "mitm/flows/")
        or ($rel == "mitm/redaction-report.json")
        or ($rel | str starts-with "mitm/reports/"))
}

# Build a flat cell list from matrix-rules.nuon.
# Mirrors `matrix list --json`: one row per
# (scenario, sender_version, receiver_version, browser) for two-party,
# or (scenario, sender_version, browser) for one-party. Includes disabled
# scenarios (placeholder universe). Does NOT call assert-scenario-enabled.
#
# Best-effort: each compute-cell call is wrapped in try/catch. On failure
# the row is warned to stderr and dropped. This differs from
# expand-matrix-cells (matrix/cells.nu) which fails hard on any cell error.
# Site ingest favors a partial result over a complete abort.
export def compute-matrix-cells [rules: record] {
    $rules.scenarios | items {|scenario, sc|
        let recv_platform = ($sc.receiver?.platform? | default "")
        let flow_id_arg = ($sc.flow_id? | default $scenario)
        let version_pairs = (expand-version-pairs $sc)
        $version_pairs | each {|vp|
            $sc.browsers | each {|browser|
                let cell = (try {
                    (compute-cell $scenario $sc.sender.platform $vp.sender_version $browser
                        $recv_platform $vp.receiver_version $flow_id_arg)
                } catch {|e|
                    print --stderr $"WARNING: compute-cell failed for ($scenario)/($vp.sender_version)/($browser): ($e.msg)"
                    null
                })
                if $cell != null {
                    $cell | merge {
                        enabled: ($sc.enabled? | default false),
                        mitm: ($sc.mitm? | default false),
                    }
                }
            } | where {|x| $x != null}
        } | flatten
    } | flatten
}
