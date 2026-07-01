# Matrix rules generator: produces in-memory matrix rules from the
# modular SSOT under config/matrix/.

use ../site/provenance.nu [build-provenance-block SITE_PROVENANCE_SOURCES]
use ../run/execution-id.nu [validate-path-segment validate-matrix-key]
use ../run/flow-ids.nu [PUBLIC_FLOW_IDS]
use ./gated-cells.nu [gate-cells-by-capabilities]
use ./status-rank.nu [STATUS_RANK pick-worst-blocker]

# Resolve version_lines for a role, falling back to the platform catalog.
def resolve-vl [flow_vl_map: record, platform: string, platforms: record] {
    let override = ($flow_vl_map | get --optional $platform)
    if $override != null {
        $override
    } else {
        ($platforms | get $platform).version_lines
    }
}

# Version-less internal lookup key for one (flow, sender, receiver?) tuple.
# Shape: <flow_id>__<sender_platform>[__<receiver_platform>]
export def matrix-key [
    flow_id: string,
    sender_platform: string,
    receiver_platform: string = "",
] {
    if ($receiver_platform | is-empty) {
        $"($flow_id)__($sender_platform)"
    } else {
        $"($flow_id)__($sender_platform)__($receiver_platform)"
    }
}

# Expand one flow record into a list of {key, entry} records.
export def expand-flow [
    flow: record,
    platforms: record,
    browsers_default: list,
] {
    let flow_id = $flow.flow_id
    if not ($flow_id in $PUBLIC_FLOW_IDS) {
        error make {msg: $"flow_id '($flow_id)' not in PUBLIC_FLOW_IDS"}
    }
    if not $flow.enabled { return [] }

    let browsers = if $flow.browsers != null { $flow.browsers } else { $browsers_default }

    let pairs = if not $flow.two_party {
        $flow.include.senders | each {|s|
            {sender: $s, receiver: null, version_pairing: null, version_pairs: null}
        }
    } else {
        $flow.include | each {|group|
            let pairing = ($group.version_pairing? | default "cross_product")
            let version_pairs = ($group.version_pairs? | default null)
            if $pairing == "explicit_pairs" {
                if ($group.sender | length) != 1 {
                    error make {msg: $"flow ($flow_id): explicit_pairs group requires exactly 1 sender platform, got ($group.sender | length)"}
                }
                if ($group.receiver | length) != 1 {
                    error make {msg: $"flow ($flow_id): explicit_pairs group requires exactly 1 receiver platform, got ($group.receiver | length)"}
                }
                let vp = ($version_pairs | default [])
                if ($vp | is-empty) {
                    let s = ($group.sender | first)
                    let r = ($group.receiver | first)
                    error make {msg: $"flow ($flow_id): explicit_pairs group sender=($s) receiver=($r) has empty version_pairs"}
                }
            }
            $group.sender | each {|s|
                $group.receiver | each {|r|
                    {sender: $s, receiver: $r, version_pairing: $pairing, version_pairs: $version_pairs}
                } | flatten
            } | flatten
        } | flatten
    }

    $pairs | each {|pair|
        let sender = $pair.sender
        let receiver = $pair.receiver

        if not ($sender in ($platforms | columns)) {
            error make {msg: $"flow ($flow_id): sender platform '($sender)' not in platforms"}
        }
        if (
            ($receiver != null)
            and (not ($receiver in ($platforms | columns)))
        ) {
            error make {msg: $"flow ($flow_id): receiver platform '($receiver)' not in platforms"}
        }

        let recv_plat = if $receiver == null { "" } else { $receiver }
        let key = (matrix-key $flow_id $sender $recv_plat)
        validate-matrix-key $key

        let sender_vl = (resolve-vl $flow.versions_sender $sender $platforms)
        if ($sender_vl | is-empty) {
            error make {msg: $"matrix ($key): sender version_lines is empty"}
        }

        let receiver_entry = if $receiver != null {
            let recv_vl = (resolve-vl $flow.versions_receiver $receiver $platforms)
            if ($recv_vl | is-empty) {
                error make {msg: $"matrix ($key): receiver version_lines is empty"}
            }
            {platform: $receiver, version_lines: $recv_vl}
        } else {
            null
        }

        let base_entry = {
            enabled: $flow.enabled,
            flow_id: $flow_id,
            browsers: $browsers,
            sender: {platform: $sender, version_lines: $sender_vl},
            receiver: $receiver_entry,
            mitm: $flow.mitm,
        }
        let pairing = ($pair.version_pairing? | default "cross_product")
        let entry = if $pairing == "explicit_pairs" {
            $base_entry
            | insert version_pairing "explicit_pairs"
            | insert version_pairs ($pair.version_pairs | default [])
        } else {
            $base_entry
        }
        {key: $key, entry: $entry}
    }
}

# Generate the matrix-rules record from the modular SSOT folder.
# matrix_dir is the path to config/matrix/ (contains defaults.nuon,
# platforms.nuon, and flows/*.nuon).
export def generate-matrix-rules [matrix_dir: string] {
    let defaults = open ($matrix_dir | path join "defaults.nuon")
    let platforms_data = open ($matrix_dir | path join "platforms.nuon")

    let browsers_default = $defaults.browsers_default
    if ($browsers_default | is-empty) {
        error make {msg: "defaults.browsers_default must be a non-empty list"}
    }

    let platforms = $platforms_data.platforms

    let flow_files = (glob ($matrix_dir | path join "flows/*.nuon") | sort)
    if ($flow_files | is-empty) {
        error make {msg: $"no flow files found under ($matrix_dir)/flows/"}
    }

    let all_pairs = ($flow_files | each {|f|
        expand-flow (open $f) $platforms $browsers_default
    } | flatten)

    # Detect duplicate matrix keys before building the output record.
    let keys = ($all_pairs | get key)
    let duplicates = ($keys | group-by {|k| $k} | items {|k, v|
        if ($v | length) > 1 { $k } else { null }
    } | where {|x| $x != null})
    if not ($duplicates | is-empty) {
        error make {msg: $"duplicate matrix keys: ($duplicates | str join ', ')"}
    }

    let matrix = ($all_pairs | each {|p| {($p.key): $p.entry}} | into record)
    {matrix: $matrix}
}

# Load the in-memory matrix rules from the SSOT folder under <root>/config/matrix/.
# Public entry point; replaces all on-disk reads of the generated matrix rules file.
export def load-matrix-rules [root: string] {
    generate-matrix-rules ($root | path join "config/matrix")
}

# --- Matrix display rule + not-in-scope emitter ---

# Map worst-status string into the display bucket label used by the matrix UI
# (supported, test-pending, vendor-unsupported, out-of-scope, placeholder).
export def classify-version-status [worst_status: string] {
    match $worst_status {
        "supported" => "supported",
        "test-implementation-pending" => "test-pending",
        "vendor-unsupported" => "vendor-unsupported",
        "vendor-out-of-scope" => "out-of-scope",
        "placeholder" => "placeholder",
        _ => {
            error make {msg: $"classify-version-status: unknown status '($worst_status)'; expected one of: supported, test-implementation-pending, vendor-unsupported, vendor-out-of-scope, placeholder"}
        },
    }
}

# Pick the cell-level worst blocker across both roles. Returns null when no
# blockers, else the blocker record with the highest precedence status.
# Delegates to pick-worst-blocker from status-rank.nu (canonical SSOT).
def cell-worst-blocker [blockers: list] {
    pick-worst-blocker $blockers
}

# Apply the matrix display rule: gate cells by capabilities, filter to visible
# cells, apply per-(flow,platform,role) version filtering, and enrich with
# tracking fields. Emits both kept_cells and not_in_scope lists.
#
# kept_cells: gate -> display_visible==true -> version filtering -> tracking enrichment.
# display_status comes from the gate helper; not recomputed locally.
# not_in_scope: gated cells with display_visible==false, reshaped per-role.
export def apply-display-rule [
    cells: list,
    adapters: record,
    flow_caps: record,
] {
    if ($cells | is-empty) {
        return {kept_cells: [], not_in_scope: []}
    }

    # Gate all cells.
    let gated = (gate-cells-by-capabilities $cells $adapters $flow_caps)

    # not_in_scope: cells with display_visible==false, reshaped per-role.
    # Deduplicate by (flow_id, platform, version, role).
    mut seen_oos = {}
    mut not_in_scope = []
    for c in ($gated | where {|g| not $g.display_visible}) {
        let oos_blockers = ($c.blockers | where {|b|
            ($b.status? | default "vendor-unsupported") == "vendor-out-of-scope"
        })
        let entries = if not ($oos_blockers | is-empty) {
            $oos_blockers | each {|b|
                let parts = ($b.adapter_key | split row "/")
                let platform = ($parts | get 0)
                let version = if ($parts | length) >= 2 { $parts | get 1 } else { "" }
                let rationale = ($b.rationale? | default (
                    $"($platform)/($version) is vendor-out-of-scope for required capabilities of ($c.flow_id)"
                ))
                {
                    flow_id: $c.flow_id,
                    platform: $platform,
                    version: $version,
                    role: $b.role,
                    rationale: $rationale,
                }
            }
        } else {
            # drift: OOS cell but no OOS blocker records
            print --stderr $"WARNING: matrix display rule drift for cell=($c.cell_id); display_visible false but no vendor-out-of-scope blockers"
            [{
                flow_id: $c.flow_id,
                platform: $c.sender_platform,
                version: $c.sender_version,
                role: "sender",
                rationale: $"drift: no vendor-out-of-scope blocker for ($c.cell_id)",
            }]
        }
        for entry in $entries {
            let key = $"($entry.flow_id)|($entry.platform)|($entry.version)|($entry.role)"
            if not ($key in $seen_oos) {
                $seen_oos = ($seen_oos | upsert $key true)
                $not_in_scope = ($not_in_scope | append $entry)
            }
        }
    }

    # Version filtering on visible cells driven by gated capability_status.
    # Placeholders always appear alongside the winning non-placeholder bucket.
    # Bucket priority for non-placeholder: supported (all) > test-pending (latest)
    # > vendor-unsupported (latest).
    let visible_cells = ($gated | where display_visible)

    # Build (flow_id, platform, version, role, capability_status) tuples from
    # the gated cells; capability_status is the gated cell's overall status so
    # enabled-coercion to placeholder is already reflected.
    let sender_tuples = ($visible_cells | each {|c|
        {
            flow_id: $c.flow_id,
            platform: $c.sender_platform,
            version: $c.sender_version,
            role: "sender",
            capability_status: $c.capability_status,
        }
    })
    let receiver_tuples = (
        $visible_cells
        | where {|c| (($c.receiver_platform? | default "") != "")}
        | each {|c|
            {
                flow_id: $c.flow_id,
                platform: $c.receiver_platform,
                version: $c.receiver_version,
                role: "receiver",
                capability_status: $c.capability_status,
            }
        }
    )
    let all_tuples = ($sender_tuples | append $receiver_tuples)

    # Status precedence rank (higher = worse). Uses canonical SSOT from status-rank.nu.
    let status_rank = $STATUS_RANK

    let groups = (
        $all_tuples
        | group-by {|r| $"($r.flow_id)|($r.platform)|($r.role)"}
    )

    # Record used as a set (key -> true) for O(1) membership checks below.
    # Keys contain "|" separators which cannot appear in record literal syntax,
    # so upsert is used for insertion.
    mut kept_keys = {}

    for kv in ($groups | transpose key val) {
        let parts = ($kv.key | split row "|")
        let flow_id = ($parts | get 0)
        let platform = ($parts | get 1)
        let role = ($parts | get 2)
        # Per version: worst capability_status across all gated cells for that version.
        # Single pass via group-by version; no per-version re-filter of the group.
        let version_statuses = ($kv.val | group-by version | transpose key val | each {|vg|
            let ranks = ($vg.val | each {|t|
                let rank = ($status_rank | get --optional $t.capability_status)
                if $rank == null {
                    error make {
                        msg: $"apply-display-rule: unknown capability_status '($t.capability_status)' for flow=($flow_id) platform=($platform) role=($role) version=($vg.key)"
                    }
                }
                $rank
            })
            let max_rank = ($ranks | math max)
            let worst_status = (
                $status_rank | transpose key rank
                | where {|r| $r.rank == $max_rank}
                | first | get key
            )
            {version: $vg.key, status: $worst_status}
        })

        let placeholder_vs = ($version_statuses | where status == "placeholder" | each {|x| $x.version})
        let supported_vs = ($version_statuses | where status == "supported" | each {|x| $x.version})
        let test_pending_vs = ($version_statuses | where {|x| $x.status == "test-implementation-pending"} | each {|x| $x.version})
        let vendor_unsupported_vs = ($version_statuses | where status == "vendor-unsupported" | each {|x| $x.version})

        # Placeholders are always kept alongside the dominant non-placeholder bucket.
        # Priority: supported (all) > test-pending (latest) > vendor-unsupported (latest).
        let non_ph_winner = if not ($supported_vs | is-empty) {
            $supported_vs
        } else if not ($test_pending_vs | is-empty) {
            [($test_pending_vs | sort | last)]
        } else if not ($vendor_unsupported_vs | is-empty) {
            [($vendor_unsupported_vs | sort | last)]
        } else {
            []
        }

        let allowed = ($placeholder_vs | append $non_ph_winner | uniq)

        if ($allowed | is-empty) {
            print --stderr $"WARNING: matrix display rule drift for flow=($flow_id) platform=($platform) role=($role); no classifiable versions"
        }

        for v in $allowed {
            $kept_keys = ($kept_keys | upsert $"($flow_id)|($platform)|($v)|($role)" true)
        }
    }

    # Filter visible cells; both sides must survive.
    let kept_cells = (
        $visible_cells
        | where {|c|
            let s_ok = ($"($c.flow_id)|($c.sender_platform)|($c.sender_version)|sender" in $kept_keys)
            let r_ok = if (($c.receiver_platform? | default "") == "") {
                true
            } else {
                ($"($c.flow_id)|($c.receiver_platform)|($c.receiver_version)|receiver" in $kept_keys)
            }
            $s_ok and $r_ok
        }
        | each {|c|
            # display_status comes from the gate; add tracking fields from worst blocker.
            let worst = (cell-worst-blocker $c.blockers)
            mut out = $c
            if $worst != null {
                let tu = ($worst.tracking_url? | default null)
                let tn = ($worst.tracking_note? | default null)
                let rt = ($worst.rationale? | default null)
                if $tu != null { $out = ($out | upsert tracking_url $tu) }
                if $tn != null { $out = ($out | upsert tracking_note $tn) }
                if $rt != null { $out = ($out | upsert rationale $rt) }
            }
            $out
        }
    )

    {kept_cells: $kept_cells, not_in_scope: $not_in_scope}
}

# Build matrix-not-in-scope.v1.json content. Groups not_in_scope entries by
# flow_id. The role field distinguishes "ocis v8 not supported as sender"
# from "as receiver"; (flow, platform, version) may appear twice if both
# roles are out-of-scope. No dedup across roles.
export def build-matrix-not-in-scope-json [not_in_scope: list, ocmts_root: string] {
    let flows = if ($not_in_scope | is-empty) {
        {}
    } else {
        $not_in_scope
        | group-by flow_id
        | transpose flow_id entries
        | each {|row|
            {
                ($row.flow_id): ($row.entries | each {|e| {
                    platform: $e.platform,
                    version: $e.version,
                    rationale: $e.rationale,
                    role: $e.role,
                }})
            }
        }
        | reduce --fold {} {|it, acc| $acc | merge $it}
    }
    let prov = (build-provenance-block {
        generator: "scripts/lib/matrix/rules-gen.nu#build-matrix-not-in-scope-json",
        producer: {name: "ocmts", version: "0.1.0"},
        sources: $SITE_PROVENANCE_SOURCES,
        ocmts_root: $ocmts_root,
    })
    $prov | merge { flows: $flows }
}
