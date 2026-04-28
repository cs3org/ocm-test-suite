# Matrix rules generator: produces in-memory matrix rules from the
# modular SSOT under config/matrix/.

use ../site/blocker-logic.nu [derive-cell-impl-info worst-status-of-blockers derive-role-blockers]
use ../site/flow-caps.nu [load-flow-caps]
use ../site/provenance.nu [build-provenance-block SITE_PROVENANCE_SOURCES]
use ../run/execution-id.nu [validate-path-segment]
use ../run/flow-ids.nu [PUBLIC_FLOW_IDS]

# Resolve version_lines for a role, falling back to the platform catalog.
def resolve-vl [flow_vl_map: record, platform: string, platforms: record] {
    let override = ($flow_vl_map | get --optional $platform)
    if $override != null {
        $override
    } else {
        ($platforms | get $platform).version_lines
    }
}

# Compute the scenario key for one (sender, receiver?) pair inside a flow.
# Applies naming.overrides, then falls back to baseline-or-derived slugs.
def scenario-key [
    flow_id: string,
    sender: string,
    receiver: any,    # null for one-party
    baseline: record, # {sender, receiver} from naming.baseline_by_flow
    platforms: record,
    overrides: record,
] {
    let is_baseline = (
        ($baseline.sender == $sender)
        and ($baseline.receiver == $receiver)
    )
    let raw_key = if $is_baseline {
        $flow_id
    } else if $receiver == null {
        let slug = ($platforms | get $sender).slug
        $"($flow_id)-($slug)"
    } else {
        let s_slug = ($platforms | get $sender).slug
        let r_slug = ($platforms | get $receiver).slug
        $"($flow_id)-($s_slug)-($r_slug)"
    }
    let mapped = ($overrides | get --optional $raw_key)
    if $mapped != null { $mapped } else { $raw_key }
}

# Expand one flow record into a list of {key, entry} records.
def expand-flow [
    flow: record,
    platforms: record,
    browsers_default: list,
    baseline_by_flow: record,
    overrides: record,
] {
    let flow_id = $flow.flow_id
    if not ($flow_id in $PUBLIC_FLOW_IDS) {
        error make {msg: $"flow_id '($flow_id)' not in PUBLIC_FLOW_IDS"}
    }

    let browsers = if $flow.browsers != null { $flow.browsers } else { $browsers_default }
    let baseline = ($baseline_by_flow | get $flow_id)

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

        let key = (scenario-key $flow_id $sender $receiver $baseline $platforms $overrides)
        validate-path-segment $key "scenario key"

        let sender_vl = (resolve-vl $flow.versions_sender $sender $platforms)
        if ($sender_vl | is-empty) {
            error make {msg: $"scenario ($key): sender version_lines is empty"}
        }

        let receiver_entry = if $receiver != null {
            let recv_vl = (resolve-vl $flow.versions_receiver $receiver $platforms)
            if ($recv_vl | is-empty) {
                error make {msg: $"scenario ($key): receiver version_lines is empty"}
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
# platforms.nuon, naming.nuon, and flows/*.nuon).
export def generate-matrix-rules [matrix_dir: string] {
    let defaults = open ($matrix_dir | path join "defaults.nuon")
    let platforms_data = open ($matrix_dir | path join "platforms.nuon")
    let naming = open ($matrix_dir | path join "naming.nuon")

    let browsers_default = $defaults.browsers_default
    if ($browsers_default | is-empty) {
        error make {msg: "defaults.browsers_default must be a non-empty list"}
    }

    let platforms = $platforms_data.platforms
    let baseline_by_flow = $naming.baseline_by_flow
    let overrides = $naming.overrides

    let flow_files = (glob ($matrix_dir | path join "flows/*.nuon") | sort)
    if ($flow_files | is-empty) {
        error make {msg: $"no flow files found under ($matrix_dir)/flows/"}
    }

    let all_pairs = ($flow_files | each {|f|
        expand-flow (open $f) $platforms $browsers_default $baseline_by_flow $overrides
    } | flatten)

    # Detect duplicate scenario keys before building the output record.
    let keys = ($all_pairs | get key)
    let duplicates = ($keys | group-by {|k| $k} | items {|k, v|
        if ($v | length) > 1 { $k } else { null }
    } | where {|x| $x != null})
    if not ($duplicates | is-empty) {
        error make {msg: $"duplicate scenario keys: ($duplicates | str join ', ')"}
    }

    let scenarios = ($all_pairs | each {|p| {($p.key): $p.entry}} | into record)
    {scenarios: $scenarios}
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
    if $worst_status == "supported" { return "supported" }
    if $worst_status == "test-implementation-pending" { return "test-pending" }
    if $worst_status == "vendor-unsupported" { return "vendor-unsupported" }
    if $worst_status == "vendor-out-of-scope" { return "out-of-scope" }
    if $worst_status == "placeholder" { return "placeholder" }
    "vendor-unsupported"
}

# Compute the worst blocker record for one (flow, platform, version, role)
# directly against role-specific required caps. Returns null when supported.
def role-worst-blocker [
    adapters: record,
    flow_caps: record,
    flow_id: string,
    platform: string,
    version: string,
    role: string,
] {
    let flow_entry = ($flow_caps | get --optional $flow_id)
    if $flow_entry == null { return null }
    let role_caps = if $role == "sender" {
        $flow_entry.sender? | default []
    } else {
        $flow_entry.receiver? | default []
    }
    if ($role_caps | is-empty) { return null }
    let adapter_key = $"($platform)/($version)"
    let blockers = (derive-role-blockers $adapters $role_caps $role $adapter_key)
    if ($blockers | is-empty) { return null }
    let rank = {
        "supported": 0,
        "placeholder": 1,
        "test-implementation-pending": 2,
        "vendor-unsupported": 3,
        "vendor-out-of-scope": 4,
    }
    let scored = ($blockers | each {|b|
        let s = ($b.status? | default "vendor-unsupported")
        let r = ($rank | get --optional $s | default 3)
        {rank: $r, blocker: $b}
    })
    let max_rank = ($scored | get rank | math max)
    ($scored | where rank == $max_rank | first | get blocker)
}

# Compute the worst status string for one (flow, platform, version, role).
def role-worst-status [
    adapters: record,
    flow_caps: record,
    flow_id: string,
    platform: string,
    version: string,
    role: string,
] {
    let flow_entry = ($flow_caps | get --optional $flow_id)
    if $flow_entry == null { return "vendor-unsupported" }
    let role_caps = if $role == "sender" {
        $flow_entry.sender? | default []
    } else {
        $flow_entry.receiver? | default []
    }
    if ($role_caps | is-empty) { return "supported" }
    let adapter_key = $"($platform)/($version)"
    let blockers = (derive-role-blockers $adapters $role_caps $role $adapter_key)
    worst-status-of-blockers $blockers
}

# Pick the cell-level worst blocker across both roles. Returns null when no
# blockers, else the blocker record with the highest precedence status.
def cell-worst-blocker [blockers: list] {
    if ($blockers | is-empty) { return null }
    let rank = {
        "supported": 0,
        "placeholder": 1,
        "test-implementation-pending": 2,
        "vendor-unsupported": 3,
        "vendor-out-of-scope": 4,
    }
    let scored = ($blockers | each {|b|
        let s = ($b.status? | default "vendor-unsupported")
        let r = ($rank | get --optional $s | default 3)
        {rank: $r, blocker: $b}
    })
    let max_rank = ($scored | get rank | math max)
    ($scored | where rank == $max_rank | first | get blocker)
}

# Apply the matrix display rule: classify each (flow, platform, role, version),
# filter cells by per-role keep-sets, and enrich kept cells with display_status
# + tracking fields. Emits both kept_cells and not_in_scope lists.
export def apply-display-rule [
    cells: list,
    adapters: record,
    flow_caps: record,
] {
    if ($cells | is-empty) {
        return {kept_cells: [], not_in_scope: []}
    }

    # Collect (flow_id, platform, version, role) tuples present in cells.
    let sender_pvs = ($cells | each {|c|
        {flow_id: $c.flow_id, platform: $c.sender_platform, version: $c.sender_version, role: "sender"}
    })
    let receiver_pvs = (
        $cells
        | where {|c| (($c.receiver_platform? | default "") != "")}
        | each {|c|
            {flow_id: $c.flow_id, platform: $c.receiver_platform, version: $c.receiver_version, role: "receiver"}
        }
    )
    let all_pvs = ($sender_pvs | append $receiver_pvs)

    # Group by (flow_id, platform, role); each group collects distinct versions.
    let groups = (
        $all_pvs
        | group-by {|r| $"($r.flow_id)|($r.platform)|($r.role)"}
    )

    mut kept_keys = []
    mut not_in_scope = []

    for kv in ($groups | transpose key val) {
        let parts = ($kv.key | split row "|")
        let flow_id = ($parts | get 0)
        let platform = ($parts | get 1)
        let role = ($parts | get 2)
        let versions = ($kv.val | each {|r| $r.version} | uniq)

        mut versions_supported = []
        mut versions_test_pending = []
        mut versions_vendor_unsupported = []
        mut versions_out_of_scope = []

        for v in $versions {
            let ws = (role-worst-status $adapters $flow_caps $flow_id $platform $v $role)
            if $ws == "supported" {
                $versions_supported = ($versions_supported | append $v)
            } else if $ws == "test-implementation-pending" {
                $versions_test_pending = ($versions_test_pending | append $v)
            } else if $ws == "vendor-unsupported" {
                $versions_vendor_unsupported = ($versions_vendor_unsupported | append $v)
            } else if $ws == "vendor-out-of-scope" {
                $versions_out_of_scope = ($versions_out_of_scope | append $v)
            }
            # other (e.g. "placeholder") falls into drift handling below
        }

        let any_visible = (
            (not ($versions_supported | is-empty))
            or (not ($versions_test_pending | is-empty))
            or (not ($versions_vendor_unsupported | is-empty))
        )

        let allowed = if not ($versions_supported | is-empty) {
            $versions_supported
        } else if not ($versions_test_pending | is-empty) {
            [($versions_test_pending | sort | last)]
        } else if not ($versions_vendor_unsupported | is-empty) {
            [($versions_vendor_unsupported | sort | last)]
        } else {
            []
        }

        for v in $allowed {
            $kept_keys = ($kept_keys | append $"($flow_id)|($platform)|($v)|($role)")
        }

        if not $any_visible {
            if not ($versions_out_of_scope | is-empty) {
                for v in $versions_out_of_scope {
                    let blocker = (role-worst-blocker $adapters $flow_caps $flow_id $platform $v $role)
                    let rationale = if $blocker != null and (($blocker.rationale? | default null) != null) {
                        $blocker.rationale
                    } else {
                        $"($platform)/($v) is vendor-out-of-scope for required capabilities of ($flow_id)"
                    }
                    $not_in_scope = ($not_in_scope | append {
                        flow_id: $flow_id,
                        platform: $platform,
                        version: $v,
                        role: $role,
                        rationale: $rationale,
                    })
                }
            } else {
                # drift: no version in any classified bucket
                print --stderr $"WARNING: matrix display rule drift for flow=($flow_id) platform=($platform) role=($role); no classifiable versions"
                for v in $versions {
                    $not_in_scope = ($not_in_scope | append {
                        flow_id: $flow_id,
                        platform: $platform,
                        version: $v,
                        role: $role,
                        rationale: $"drift: no classifiable status for ($platform)/($v) in ($flow_id) as ($role)",
                    })
                }
            }
        }
    }

    # Filter cells; both sides must survive.
    let kept_cells = (
        $cells
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
            let info = (derive-cell-impl-info $c $adapters $flow_caps)
            let enabled = ($c.enabled? | default false)
            let display_status = if not $enabled {
                "placeholder"
            } else {
                worst-status-of-blockers $info.blockers
            }
            let worst = (cell-worst-blocker $info.blockers)
            mut out = ($c | upsert display_status $display_status)
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
