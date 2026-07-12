# Image config reference validator.
# Walks config/images.nuon and flags by_flow / by_matrix_key entries that
# reference unknown flow IDs or matrix keys. Orphan SSOT keys are not errors.

use ../matrix/rules-gen.nu [load-matrix-rules]

def list-flow-ids [root: string] {
    let flows_dir = ($root | path join "config/matrix/flows")
    let files = (glob ($flows_dir | path join "*.nuon"))
    if ($files | is-empty) {
        return []
    }
    $files | each {|f| (open $f).flow_id }
}

def collect-scope-keys [scope: record, location: string, kind: string] {
    if ($scope | is-empty) {
        return []
    }
    $scope
    | columns
    | each {|key|
        {key: $key, location: $location, kind: $kind}
    }
}

def collect-version-spec-keys [
    version_spec: record,
    location_prefix: string,
] {
    mut out = []
    $out = ($out | append (collect-scope-keys
        ($version_spec.by_flow? | default {})
        $"($location_prefix).by_flow"
        "by_flow"))
    $out = ($out | append (collect-scope-keys
        ($version_spec.by_matrix_key? | default {})
        $"($location_prefix).by_matrix_key"
        "by_matrix_key"))
    let bundle = ($version_spec.bundle? | default {})
    for slot in ($bundle | columns) {
        let slot_spec = ($bundle | get $slot)
        let slot_loc = $"($location_prefix).bundle.($slot)"
        $out = ($out | append (collect-scope-keys
            ($slot_spec.by_flow? | default {})
            $"($slot_loc).by_flow"
            "by_flow"))
        $out = ($out | append (collect-scope-keys
            ($slot_spec.by_matrix_key? | default {})
            $"($slot_loc).by_matrix_key"
            "by_matrix_key"))
    }
    $out
}

def collect-image-reference-keys [images_cfg: record] {
    let platforms = ($images_cfg.platforms? | default {})
    $platforms
    | items {|platform, versions|
        $versions
        | items {|version, version_spec|
            collect-version-spec-keys $version_spec $"platforms.($platform).($version)"
        }
        | flatten
    }
    | flatten
}

def unknown-flow-entries [refs: list, valid_flow_ids: list] {
    $refs
    | where kind == "by_flow"
    | where {|r| not ($r.key in $valid_flow_ids)}
}

def unknown-matrix-entries [refs: list, valid_matrix_keys: list] {
    $refs
    | where kind == "by_matrix_key"
    | where {|r| not ($r.key in $valid_matrix_keys)}
}

export def validate-images-cfg [root: string] {
    let images_path = ($root | path join "config/images.nuon")
    let images_cfg = (open $images_path)
    let refs = (collect-image-reference-keys $images_cfg)

    let valid_flow_ids = (list-flow-ids $root)

    let rules = (load-matrix-rules $root)
    let valid_matrix_keys = ($rules.matrix | columns)

    let unknown_flow_keys = (unknown-flow-entries $refs $valid_flow_ids
        | each {|r| {key: $r.key, location: $r.location}})
    let unknown_matrix_keys = (unknown-matrix-entries $refs $valid_matrix_keys
        | each {|r| {key: $r.key, location: $r.location}})

    {
        ok: (($unknown_flow_keys | is-empty) and ($unknown_matrix_keys | is-empty)),
        unknown_flow_keys: $unknown_flow_keys,
        unknown_matrix_keys: $unknown_matrix_keys,
    }
}
