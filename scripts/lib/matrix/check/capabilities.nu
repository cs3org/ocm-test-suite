# Drift checker orchestrator. Reads the capabilities SSOT, validates
# schema, runs all sub-checks, and returns a unified result record.
# The CLI wrapper in scripts/domains/matrix/mod.nu handles printing
# and exit codes.

use ./platforms.nu [check-platform-completeness]
use ./completeness.nu [check-capability-completeness]
use ./flow-drift.nu [check-capability-name-drift]
use ./registry-cross.nu [extract-registry-tables build-expected-supported diff-registry-vs-supported registry-bound-capabilities check-registry-table-coverage]
use ./warnings.nu [collect-status-warnings]
use ./provenance.nu [check-provenance-blocks]

const CAPABILITY_STATUSES = [
    "supported",
    "vendor-unsupported",
    "vendor-out-of-scope",
    "test-implementation-pending",
    "placeholder",
]

const ALLOWED_ENTRY_KEYS = ["status", "rationale", "tracking_note", "tracking_url"]

# Validates SSOT shape and returns {adapters, supported_by_key, adapter_cap_keys}.
# Throws via error make on schema violations.
def parse-and-validate-ssot [path: string] {
    let raw = (open $path)
    if not (($raw | describe) | str starts-with "record") {
        error make {msg: $"($path): top-level value must be an object"}
    }
    if ($raw.schema_version? | default null) != 1 {
        error make {msg: $"($path): unsupported schema_version (expected 1), got ($raw.schema_version?)"}
    }
    let adapters_in = ($raw.adapters? | default null)
    if $adapters_in == null or (not (($adapters_in | describe) | str starts-with "record")) {
        error make {msg: $"($path): \"adapters\" must be an object"}
    }

    mut adapters_out = {}
    mut supported_by_key = {}
    mut adapter_cap_keys = []
    let adapter_rows = ($adapters_in | transpose adapter_key entry)
    for $row in $adapter_rows {
        let ak = $row.adapter_key
        let entry = $row.entry
        if not (($entry | describe) | str starts-with "record") {
            error make {msg: $"($path): \"adapters.($ak)\" must be an object"}
        }
        let caps_in = ($entry.capabilities? | default null)
        if $caps_in == null or (not (($caps_in | describe) | str starts-with "record")) {
            error make {msg: $"($path): \"adapters.($ak).capabilities\" must be an object"}
        }

        mut caps_out = {}
        mut supported_here = []
        let cap_rows = ($caps_in | transpose cap_key cap_value)
        for $crow in $cap_rows {
            let ck = $crow.cap_key
            let cv = $crow.cap_value
            if not (($cv | describe) | str starts-with "record") {
                error make {msg: $"($path): \"adapters.($ak).capabilities.($ck)\" must be an object"}
            }
            let unknown_keys = (($cv | columns) | where {|k| not ($k in $ALLOWED_ENTRY_KEYS)})
            if ($unknown_keys | length) > 0 {
                error make {msg: $"($path): \"adapters.($ak).capabilities.($ck)\" has unknown fields: (($unknown_keys | str join ', '))"}
            }
            let status = ($cv.status? | default null)
            if (($status | describe) != "string") or (not ($status in $CAPABILITY_STATUSES)) {
                error make {msg: $"($path): \"adapters.($ak).capabilities.($ck).status\" must be one of: (($CAPABILITY_STATUSES | str join ', ')). Got: ($status)"}
            }
            for $opt in ["rationale", "tracking_note", "tracking_url"] {
                let v = ($cv | get --optional $opt)
                if ($v != null) and (($v | describe) != "string") {
                    error make {msg: $"($path): \"adapters.($ak).capabilities.($ck).($opt)\" must be a string if present"}
                }
            }
            $caps_out = ($caps_out | upsert $ck $cv)
            if $status == "supported" {
                $supported_here = ($supported_here | append $ck)
            }
            if not ($ck in $adapter_cap_keys) {
                $adapter_cap_keys = ($adapter_cap_keys | append $ck)
            }
        }
        $adapters_out = ($adapters_out | upsert $ak {capabilities: $caps_out})
        $supported_by_key = ($supported_by_key | upsert $ak ($supported_here | uniq | sort))
    }
    {adapters: $adapters_out, supported_by_key: $supported_by_key, adapter_cap_keys: ($adapter_cap_keys | sort)}
}

# Main entry. Returns a result record:
# {ok, platforms, completeness, flow_drift, registry_cross, provenance, warnings}.
export def check-adapter-capabilities [ocmts_root: string] {
    let caps_path = ($ocmts_root | path join "config/adapters/capabilities.v1.nuon")
    if not ($caps_path | path exists) {
        error make {msg: $"config/adapters/capabilities.v1.nuon: file not found"}
    }
    let ssot = (parse-and-validate-ssot $caps_path)

    # Registry cross-check uses the live registry.ts.
    # Filter supported_by_key to only capabilities that have a registry table,
    # so orchestration-only flow.* caps do not appear in drift output.
    let registry_path = ($ocmts_root | path join "cypress/support/adapters/registry.ts")
    let tables = (extract-registry-tables $ocmts_root $registry_path)
    check-registry-table-coverage $tables.tables
    let expected = (build-expected-supported $tables)
    let bound_caps = (registry-bound-capabilities)
    let registry_supported = ($ssot.supported_by_key
        | transpose adapter_key caps
        | each {|row|
            {adapter_key: $row.adapter_key, caps: ($row.caps | where {|c| $c in $bound_caps})}
        }
        | where {|row| ($row.caps | length) > 0}
        | reduce --fold {} {|row, acc|
            $acc | upsert $row.adapter_key $row.caps
        })
    let registry_cross = (diff-registry-vs-supported $expected $registry_supported)

    let adapter_keys = ($ssot.adapters | columns | sort)
    let platforms = (check-platform-completeness $ocmts_root $adapter_keys)
    let completeness = (check-capability-completeness $ocmts_root $ssot.adapters)
    let flow_drift = (check-capability-name-drift $ocmts_root $completeness.canonical $ssot.adapter_cap_keys)
    let provenance = (check-provenance-blocks $ocmts_root)
    let warnings = (collect-status-warnings $ssot.adapters)

    let has_errors = (
        (($platforms.missing_from_json | length) > 0)
        or (($platforms.extra_in_json | length) > 0)
        or (($completeness.missing | length) > 0)
        or (($flow_drift.unknown_names | length) > 0)
        or (($flow_drift.shape_violations? | default [] | length) > 0)
        or (($registry_cross.missing_keys | length) > 0)
        or (($registry_cross.extra_keys | length) > 0)
        or (($registry_cross.drift | length) > 0)
        or (($provenance.violations | length) > 0)
    )

    {
        ok: (not $has_errors),
        platforms: $platforms,
        completeness: $completeness,
        flow_drift: $flow_drift,
        registry_cross: $registry_cross,
        provenance: $provenance,
        warnings: $warnings,
    }
}
