# Cell implementation info: expand matrix cells and evaluate adapter capabilities.

use ./internal.nu [compute-matrix-cells]
use ./provenance.nu [build-provenance-block SITE_PROVENANCE_SOURCES]
use ./flow-caps.nu [load-flow-caps]

# Re-export shared blocker evaluation helpers (implementations live in
# blocker-logic.nu to avoid circular imports with matrix/rules-gen.nu).
export use ./blocker-logic.nu [worst-status-of-blockers derive-role-blockers derive-cell-impl-info]

# Build the per-cell record for implemented-cells.v1.json from a precomputed
# cell list. Each cell value emits display_status, blocked_by (public view),
# implemented (back-compat boolean), plus legacy requirements/blockers fields
# unchanged for back-compat.
export def build-implemented-cells-record [
    cell_list: list,
    adapters: record,
    flow_caps: record,
] {
    if ($cell_list | is-empty) { return {} }
    ($cell_list | each {|c|
        let impl_info = (derive-cell-impl-info $c $adapters $flow_caps)
        let enabled = ($c.enabled? | default false)
        let display_status = if not $enabled {
            "placeholder"
        } else {
            worst-status-of-blockers $impl_info.blockers
        }
        let blocked_by = ($impl_info.blockers | each {|b|
            mut out = {
                role: ($b.role? | default ""),
                capability: ($b.capability? | default ""),
                status: ($b.status? | default ""),
            }
            let tu = ($b.tracking_url? | default null)
            let tn = ($b.tracking_note? | default null)
            let rt = ($b.rationale? | default null)
            if $tu != null { $out = ($out | upsert tracking_url $tu) }
            if $tn != null { $out = ($out | upsert tracking_note $tn) }
            if $rt != null { $out = ($out | upsert rationale $rt) }
            $out
        })
        {
            ($c.cell_id): {
                scenario: $c.scenario,
                flow_id: $c.flow_id,
                pair: $c.pair,
                browser: $c.browser,
                sender_platform: $c.sender_platform,
                sender_version: $c.sender_version,
                receiver_platform: $c.receiver_platform,
                receiver_version: $c.receiver_version,
                artifact_name: $c.artifact_name,
                mitm: $c.mitm,
                display_status: $display_status,
                blocked_by: $blocked_by,
                implemented: ($display_status == "supported"),
                requirements: $impl_info.requirements,
                blockers: $impl_info.blockers,
            }
        }
    } | into record)
}

# Build implemented-cells.v1.json content.
# Accepts pre-loaded rules, adapters, and flow_caps to avoid re-reading the filesystem.
export def build-implemented-cells-json [
    rules: record,
    adapters: record,
    flow_caps: record,
    ocmts_root: string,
] {
    let cell_list = (compute-matrix-cells $rules)
    let cells = (build-implemented-cells-record $cell_list $adapters $flow_caps)
    let prov = (build-provenance-block {
        generator: "scripts/lib/site/cell-impl.nu#build-implemented-cells-json",
        producer: {name: "ocmts", version: "0.1.0"},
        sources: $SITE_PROVENANCE_SOURCES,
        ocmts_root: $ocmts_root,
    })
    $prov | merge { cells: $cells }
}
