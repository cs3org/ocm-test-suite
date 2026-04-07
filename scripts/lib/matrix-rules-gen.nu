# Matrix rules generator: produces config/matrix-rules.nuon from the
# modular SSOT under config/matrix/.

use ./execution-id.nu [validate-path-segment]
use ./flow-ids.nu [PUBLIC_FLOW_IDS]

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

# Write the generated matrix-rules record as strict JSON to out_path.
export def write-generated-matrix-rules [matrix_dir: string, out_path: string] {
    let rules = (generate-matrix-rules $matrix_dir)
    $rules | to json --indent 2 | save --force $out_path
}
