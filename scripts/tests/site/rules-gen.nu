# Tests for the matrix display rule and not-in-scope emitter.
# Run: nu scripts/tests/site/rules-gen.nu

const SUITE_PATH = path self

use ../../lib/matrix/rules-gen.nu [
    apply-display-rule
    build-matrix-not-in-scope-json
    classify-version-status
    expand-flow
]
use ../../lib/matrix/gated-cells.nu [gate-cells-by-capabilities]
use ../../lib/site/manifest.nu [build-matrix-rules-json]
use ../../lib/tests/assert.nu *
use ../../lib/tests/fixtures.nu [materialize-provenance-stubs]
use ../../lib/tests/runner.nu [run-suite]

# Write full-fidelity flow stubs (all required fields) over the minimal stubs
# created by materialize-provenance-stubs, so build-matrix-rules-json can
# validate and read them without error.
def fill-flow-stubs [tmp_root: string] {
    let flows = [
        {stem: "code-flow",     label: "Code Flow",       subtitle: "Code flow",      order: 30, enabled: false, two_party: true,  mitm: false}
        {stem: "contact-token", label: "Contact Token",   subtitle: "Token flow",     order: 40, enabled: false, two_party: true,  mitm: false}
        {stem: "contact-wayf",  label: "Contact WAYF",    subtitle: "WAYF flow",      order: 50, enabled: false, two_party: true,  mitm: false}
        {stem: "login",         label: "Login Flow",      subtitle: "Login flow",     order: 10, enabled: true,  two_party: false, mitm: false}
        {stem: "share-with",    label: "Share With Flow", subtitle: "Share-with flow", order: 20, enabled: true,  two_party: true,  mitm: true}
    ]
    for s in $flows {
        let flow = {
            flow_id: $s.stem,
            label: $s.label,
            subtitle: $s.subtitle,
            display_order: $s.order,
            enabled: $s.enabled,
            two_party: $s.two_party,
            mitm: $s.mitm,
            required_capabilities: {sender: [], receiver: []}
        }
        $flow | to nuon | save --force ($tmp_root | path join "config/matrix/flows" $"($s.stem).nuon")
    }
}

# Make a synthetic cell. Mirrors what compute-matrix-cells would emit.
def make-cell [
    --flow_id: string = "share-with",
    --scenario: string = "share-with",
    --sender_platform: string = "nextcloud",
    --sender_version: string = "v34",
    --receiver_platform: string = "",
    --receiver_version: string = "",
    --enabled = true,
    --browser: string = "chrome",
    --mitm = false,
] {
    let is_two_party = (not ($receiver_platform | is-empty))
    let cell_id = if $is_two_party {
        $"($flow_id)__($sender_platform)-($sender_version)__($receiver_platform)-($receiver_version)"
    } else {
        $"($flow_id)__($sender_platform)-($sender_version)"
    }
    let pair = if $is_two_party {
        $"($sender_platform)-($sender_version)-($receiver_platform)-($receiver_version)"
    } else {
        $"($sender_platform)-($sender_version)"
    }
    let artifact_name = if $is_two_party {
        $"cell-($flow_id)-($sender_platform)-($sender_version)-($receiver_platform)-($receiver_version)"
    } else {
        $"cell-($flow_id)-($sender_platform)-($sender_version)"
    }
    {
        flow_id: $flow_id,
        scenario: $scenario,
        scenario_module: $flow_id,
        cell_id: $cell_id,
        artifact_name: $artifact_name,
        pair: $pair,
        sender_platform: $sender_platform,
        sender_version: $sender_version,
        receiver_platform: $receiver_platform,
        receiver_version: $receiver_version,
        browser: $browser,
        is_two_party: $is_two_party,
        enabled: $enabled,
        mitm: $mitm,
    }
}

def fixture-share-with-flow-caps [] {
    {
        "share-with": {
            sender: ["flow.share-with.sender", "op.login", "op.share-file.sender"],
            receiver: ["flow.share-with.receiver", "op.login", "op.share-file.receiver"],
        },
        "code-flow": {
            sender: ["op.login", "flow.code-flow.sender"],
            receiver: ["op.login", "flow.code-flow.receiver"],
        },
        "contact-wayf": {
            sender: ["flow.contact-wayf.sender", "op.login", "op.contact-wayf.sender", "op.share-file.sender"],
            receiver: ["flow.contact-wayf.receiver", "op.login", "op.contact-wayf.receiver", "op.provider-identity", "op.share-file.receiver"],
        },
    }
}

# When v34 (supported) exists alongside v32, v33 (vendor-unsupported), keep only v34.
def test-apply-display-rule-keeps-supported-only [] {
    test-log "\n[test-apply-display-rule-keeps-supported-only]"
    let adapters = {
        "nextcloud/v32": {
            capabilities: {
                "op.login": {status: "supported"},
                "flow.share-with.sender": {status: "vendor-unsupported"},
                "flow.share-with.receiver": {status: "vendor-unsupported"},
                "op.share-file.sender": {status: "supported"},
                "op.share-file.receiver": {status: "supported"},
            }
        },
        "nextcloud/v33": {
            capabilities: {
                "op.login": {status: "supported"},
                "flow.share-with.sender": {status: "vendor-unsupported"},
                "flow.share-with.receiver": {status: "vendor-unsupported"},
                "op.share-file.sender": {status: "supported"},
                "op.share-file.receiver": {status: "supported"},
            }
        },
        "nextcloud/v34": {
            capabilities: {
                "op.login": {status: "supported"},
                "flow.share-with.sender": {status: "supported"},
                "flow.share-with.receiver": {status: "supported"},
                "op.share-file.sender": {status: "supported"},
                "op.share-file.receiver": {status: "supported"},
            }
        },
    }
    let cells = [
        (make-cell --sender_version "v32" --receiver_platform "nextcloud" --receiver_version "v32")
        (make-cell --sender_version "v33" --receiver_platform "nextcloud" --receiver_version "v33")
        (make-cell --sender_version "v34" --receiver_platform "nextcloud" --receiver_version "v34")
    ]
    let result = (apply-display-rule $cells $adapters (fixture-share-with-flow-caps))
    let versions_kept = ($result.kept_cells | each {|c| $c.sender_version} | uniq | sort)
    [
        (assert-eq $versions_kept ["v34"]
            "only v34 kept when supported exists")
        (assert-eq ($result.not_in_scope | length) 0
            "no not_in_scope entries for vendor-unsupported when supported exists")
    ]
}

# When only test-pending exists (multiple versions), keep latest only.
def test-apply-display-rule-keeps-latest-test-pending [] {
    test-log "\n[test-apply-display-rule-keeps-latest-test-pending]"
    let adapters = {
        "opencloud/v5": {
            capabilities: {
                "op.login": {status: "supported"},
                "flow.share-with.sender": {status: "test-implementation-pending"},
                "flow.share-with.receiver": {status: "test-implementation-pending"},
                "op.share-file.sender": {status: "supported"},
                "op.share-file.receiver": {status: "supported"},
            }
        },
        "opencloud/v6": {
            capabilities: {
                "op.login": {status: "supported"},
                "flow.share-with.sender": {status: "test-implementation-pending"},
                "flow.share-with.receiver": {status: "test-implementation-pending"},
                "op.share-file.sender": {status: "supported"},
                "op.share-file.receiver": {status: "supported"},
            }
        },
    }
    let cells = [
        (make-cell --sender_platform "opencloud" --sender_version "v5" --receiver_platform "opencloud" --receiver_version "v5")
        (make-cell --sender_platform "opencloud" --sender_version "v6" --receiver_platform "opencloud" --receiver_version "v6")
    ]
    let result = (apply-display-rule $cells $adapters (fixture-share-with-flow-caps))
    let kept_versions = ($result.kept_cells | each {|c| $c.sender_version} | uniq | sort)
    let display_statuses = ($result.kept_cells | each {|c| $c.display_status} | uniq)
    [
        (assert-eq $kept_versions ["v6"]
            "only latest test-pending version v6 kept")
        (assert-truthy ("test-pending" in $display_statuses)
            "kept cell has test-pending display_status")
    ]
}

# Vendor-out-of-scope drops the (flow, platform, role) entirely and lands in not_in_scope.
def test-apply-display-rule-emits-not-in-scope [] {
    test-log "\n[test-apply-display-rule-emits-not-in-scope]"
    let adapters = {
        "seafile/v1": {
            capabilities: {
                "op.login": {status: "supported"},
                "flow.code-flow.sender": {
                    status: "vendor-out-of-scope",
                    rationale: "seafile does not implement OCM code-flow",
                },
                "flow.code-flow.receiver": {
                    status: "vendor-out-of-scope",
                    rationale: "seafile does not implement OCM code-flow",
                },
            }
        },
        "nextcloud/v34": {
            capabilities: {
                "op.login": {status: "supported"},
                "flow.code-flow.sender": {status: "supported"},
                "flow.code-flow.receiver": {status: "supported"},
            }
        },
    }
    let cells = [
        (make-cell --flow_id "code-flow" --scenario "code-flow-seafile" --sender_platform "seafile" --sender_version "v1" --receiver_platform "nextcloud" --receiver_version "v34")
    ]
    let result = (apply-display-rule $cells $adapters (fixture-share-with-flow-caps))
    let seafile_kept = ($result.kept_cells | where {|c| $c.sender_platform == "seafile"})
    let seafile_oos = ($result.not_in_scope
        | where {|e| ($e.flow_id == "code-flow") and ($e.platform == "seafile") and ($e.version == "v1")})
    let roles = ($seafile_oos | each {|e| $e.role} | uniq | sort)
    [
        (assert-truthy ($seafile_kept | is-empty)
            "seafile cells dropped from kept_cells")
        (assert-truthy (not ($seafile_oos | is-empty))
            "seafile/v1 lands in not_in_scope for code-flow")
        (assert-truthy ("sender" in $roles)
            "not_in_scope entry covers sender role")
        (assert-eq ($seafile_oos | first | get rationale)
            "seafile does not implement OCM code-flow"
            "rationale propagated from worst blocker")
    ]
}

# build-matrix-rules-json emits display_status on every scenario; never out-of-scope.
def test-build-matrix-rules-json-includes-display-status [] {
    test-log "\n[test-build-matrix-rules-json-includes-display-status]"
    # build-matrix-rules-json calls compute-matrix-cells internally, which
    # hits the filesystem via compute-cell's topology guard. To keep this
    # test hermetic, we exercise apply-display-rule directly with synthetic
    # cells and assert the same downstream invariants: every kept cell has
    # a display_status, and none is vendor-out-of-scope.
    let adapters = {
        "nextcloud/v34": {
            capabilities: {
                "op.login": {status: "supported"},
                "flow.share-with.sender": {status: "supported"},
                "flow.share-with.receiver": {status: "supported"},
                "op.share-file.sender": {status: "supported"},
                "op.share-file.receiver": {status: "supported"},
            }
        },
        "opencloud/v6": {
            capabilities: {
                "op.login": {status: "supported"},
                "flow.share-with.sender": {status: "test-implementation-pending"},
                "flow.share-with.receiver": {status: "test-implementation-pending"},
                "op.share-file.sender": {status: "supported"},
                "op.share-file.receiver": {status: "supported"},
            }
        },
        "ocis/v8": {
            capabilities: {
                "op.login": {status: "supported"},
                "flow.share-with.sender": {
                    status: "vendor-out-of-scope",
                    rationale: "ocis requires prior contact-token",
                },
                "flow.share-with.receiver": {
                    status: "vendor-out-of-scope",
                    rationale: "ocis requires prior contact-token",
                },
                "op.share-file.sender": {status: "supported"},
                "op.share-file.receiver": {status: "supported"},
            }
        },
    }
    let cells = [
        (make-cell --sender_version "v34" --receiver_platform "nextcloud" --receiver_version "v34")
        (make-cell --sender_platform "opencloud" --sender_version "v6" --receiver_platform "opencloud" --receiver_version "v6")
        (make-cell --sender_platform "ocis" --sender_version "v8" --receiver_platform "nextcloud" --receiver_version "v34")
    ]
    let result = (apply-display-rule $cells $adapters (fixture-share-with-flow-caps))
    let visible = ["supported", "test-pending", "vendor-unsupported", "placeholder"]
    let all_have_status = ($result.kept_cells | all {|c| ($c.display_status? | default "") != ""})
    let none_oos = ($result.kept_cells | all {|c| $c.display_status != "out-of-scope"})
    let all_in_visible = ($result.kept_cells | all {|c| $c.display_status in $visible})
    let ocis_kept = ($result.kept_cells | any {|c| $c.sender_platform == "ocis"})
    [
        (assert-truthy $all_have_status
            "every kept cell has a display_status field")
        (assert-truthy $none_oos
            "no kept cell has display_status == vendor-out-of-scope")
        (assert-truthy $all_in_visible
            "every display_status is one of the 4 visible enum values")
        (assert-truthy (not $ocis_kept)
            "ocis cells filtered out by display rule")
    ]
}

# build-matrix-not-in-scope-json top-level shape.
def test-build-matrix-not-in-scope-json-shape [] {
    test-log "\n[test-build-matrix-not-in-scope-json-shape]"
    let not_in_scope = [
        {flow_id: "code-flow", platform: "seafile", version: "v1", role: "sender", rationale: "r1"}
        {flow_id: "code-flow", platform: "seafile", version: "v1", role: "receiver", rationale: "r1"}
        {flow_id: "share-with", platform: "ocis", version: "v8", role: "sender", rationale: "r2"}
    ]
    mut tmp = ($nu.temp-path | path join $"ocmts-prov-(random uuid)")
    mkdir $tmp
    materialize-provenance-stubs $tmp
    let out = (build-matrix-not-in-scope-json $not_in_scope $tmp)
    let cols = ($out | columns | sort)
    let code_flow_entries = ($out.flows | get "code-flow")
    let share_with_entries = ($out.flows | get "share-with")
    let code_flow_roles = ($code_flow_entries | each {|e| $e.role} | sort)
    let hex_re = '^[0-9a-f]{64}$'
    let result = [
        (assert-eq $out.schema_version 1
            "schema_version is 1")
        (assert-eq $cols ["flows", "generated_at", "generator", "producer", "schema_version", "sources"]
            "top-level columns include provenance fields")
        (assert-eq $out.generator
            "scripts/lib/matrix/rules-gen.nu#build-matrix-not-in-scope-json"
            "generator points at this writer")
        (assert-eq $out.producer {name: "ocmts", version: "0.1.0"}
            "producer matches uniform constant")
        (assert-eq ($out.sources | length) 10
            "sources has 10 entries")
        (assert-eq ($out.sources | first | columns | sort) ["path", "sha256"]
            "each source entry has path and sha256 keys")
        (assert-truthy ($out.sources | all {|s| not ($s.path | str starts-with "/")})
            "no source path is absolute")
        (assert-truthy ($out.sources | all {|s| ($s.sha256 | parse --regex $hex_re | length) == 1})
            "every sha256 matches 64-hex pattern")
        (assert-eq ($code_flow_entries | length) 2
            "code-flow flow has two entries (sender + receiver)")
        (assert-eq $code_flow_roles ["receiver", "sender"]
            "code-flow entries cover both roles")
        (assert-eq ($share_with_entries | length) 1
            "share-with flow has one entry")
    ]
    rm --recursive --force $tmp
    $result
}

def test-build-matrix-rules-json-provenance-shape [] {
    test-log "\n[test-build-matrix-rules-json-provenance-shape]"
    mut tmp = ($nu.temp-path | path join $"ocmts-prov-(random uuid)")
    mkdir $tmp
    materialize-provenance-stubs $tmp
    fill-flow-stubs $tmp
    let rules = {scenarios: {}}
    let out = (build-matrix-rules-json $rules "config/matrix" {} {} $tmp)
    let rfc_re = '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{9}Z$'
    let hex_re = '^[0-9a-f]{64}$'
    let result = [
        (assert-eq $out.schema_version 1
            "schema_version is 1")
        (assert-eq $out.generator
            "scripts/lib/site/manifest.nu#build-matrix-rules-json"
            "generator points at this writer")
        (assert-eq $out.producer {name: "ocmts", version: "0.1.0"}
            "producer matches uniform constant")
        (assert-eq ($out.sources | length) 10
            "sources has 10 entries")
        (assert-eq ($out.sources | first | columns | sort) ["path", "sha256"]
            "each source entry has path and sha256 keys")
        (assert-truthy ($out.sources | all {|s| not ($s.path | str starts-with "/")})
            "no source path is absolute")
        (assert-truthy ($out.sources | all {|s| ($s.sha256 | parse --regex $hex_re | length) == 1})
            "every sha256 matches 64-hex pattern")
        (assert-eq $out.source "config/matrix"
            "source back-compat field is rules_path")
        (assert-truthy (($out.generated_at | parse --regex $rfc_re | length) == 1)
            "generated_at matches RFC3339 nanosecond format")
    ]
    rm --recursive --force $tmp
    $result
}

def test-expand-flow-skips-disabled-flow [] {
    test-log "\n[test-expand-flow-skips-disabled-flow]"
    let platforms = {p1: {slug: "p1", version_lines: ["v1"]}}
    let baseline_by_flow = {"code-flow": {sender: "p1", receiver: "p1"}}
    let overrides = {}
    let browsers_default = ["chrome"]
    let disabled_flow = {
        flow_id: "code-flow",
        enabled: false,
        two_party: true,
        browsers: null,
        mitm: true,
        include: [{sender: ["p1"], receiver: ["p1"]}],
        versions_sender: {p1: ["v1"]},
        versions_receiver: {p1: ["v1"]},
    }
    let enabled_flow = {
        flow_id: "code-flow",
        enabled: true,
        two_party: true,
        browsers: null,
        mitm: true,
        include: [{sender: ["p1"], receiver: ["p1"]}],
        versions_sender: {p1: ["v1"]},
        versions_receiver: {p1: ["v1"]},
    }
    let disabled_result = (expand-flow $disabled_flow $platforms $browsers_default $baseline_by_flow $overrides)
    let enabled_result = (expand-flow $enabled_flow $platforms $browsers_default $baseline_by_flow $overrides)
    [
        (assert-eq $disabled_result [] "disabled flow returns empty list")
        (assert-truthy (not ($enabled_result | is-empty)) "enabled flow returns non-empty list")
    ]
}

def test-build-matrix-rules-json-emits-flows-and-platforms [] {
    test-log "\n[test-build-matrix-rules-json-emits-flows-and-platforms]"
    mut tmp = ($nu.temp-path | path join $"ocmts-flows-(random uuid)")
    mkdir $tmp
    materialize-provenance-stubs $tmp
    fill-flow-stubs $tmp
    # Overwrite platforms.nuon with 2 platforms that have display_name.
    ({
        schema_version: 1,
        platforms: {
            alpha: {slug: "alp", display_name: "Alpha Platform", version_lines: ["v1"]},
            beta:  {slug: "bet", display_name: "Beta Platform",  version_lines: ["v2"]},
        }
    } | to nuon) | save --force ($tmp | path join "config/matrix/platforms.nuon")
    let out = (build-matrix-rules-json {scenarios: {}} "config/matrix" {} {} $tmp)
    let required_flow_keys = (["flow_id" "label" "subtitle" "display_order" "enabled" "two_party" "mitm"] | sort)
    let required_plat_keys = (["id" "display_name" "slug" "version_lines"] | sort)
    let first_flow_cols = ($out.flows | first | columns | sort)
    let first_plat_cols = ($out.platforms | first | columns | sort)
    let display_orders = ($out.flows | each {|f| $f.display_order})
    let sorted_orders = ($display_orders | sort)
    let result = [
        (assert-eq ($out.flows | length) 5
            "flows has one entry per flow file (5 total)")
        (assert-eq $first_flow_cols $required_flow_keys
            "first flow has required keys")
        (assert-eq $display_orders $sorted_orders
            "flows sorted by display_order ascending")
        (assert-eq ($out.platforms | length) 2
            "platforms has 2 entries")
        (assert-eq $first_plat_cols $required_plat_keys
            "first platform has required keys")
    ]
    rm --recursive --force $tmp
    $result
}

def test-build-matrix-rules-json-rejects-empty-flows-dir [] {
    test-log "\n[test-build-matrix-rules-json-rejects-empty-flows-dir]"
    mut tmp = ($nu.temp-path | path join $"ocmts-emptyflows-(random uuid)")
    mkdir ($tmp | path join "config/matrix/flows")
    let err = (try {
        build-matrix-rules-json {scenarios: {}} "config/matrix" {} {} $tmp
    } catch {|e| $e.msg})
    let result = [
        (assert-string-contains $err "no flow files found under" "error mentions no flow files")
        (assert-string-contains $err "expected at least one *.nuon" "error mentions expected nuon pattern")
    ]
    rm --recursive --force $tmp
    $result
}

def test-build-matrix-rules-json-rejects-missing-platforms [] {
    test-log "\n[test-build-matrix-rules-json-rejects-missing-platforms]"
    mut tmp = ($nu.temp-path | path join $"ocmts-noplat-(random uuid)")
    mkdir $tmp
    materialize-provenance-stubs $tmp
    # Overwrite with a file that has no platforms key at all.
    ({schema_version: 1} | to nuon) | save --force ($tmp | path join "config/matrix/platforms.nuon")
    let err = (try {
        build-matrix-rules-json {scenarios: {}} "config/matrix" {} {} $tmp
    } catch {|e| $e.msg})
    let result = [
        (assert-string-contains $err "has no 'platforms' record or it is empty" "error mentions missing platforms")
        (assert-string-contains $err "config/matrix" "error includes rules_path")
    ]
    rm --recursive --force $tmp
    $result
}

def test-build-matrix-rules-json-rejects-platform-missing-keys [] {
    test-log "\n[test-build-matrix-rules-json-rejects-platform-missing-keys]"
    mut tmp = ($nu.temp-path | path join $"ocmts-missingkeys-(random uuid)")
    mkdir $tmp
    materialize-provenance-stubs $tmp
    # Platform with display_name and version_lines but no slug.
    ({
        schema_version: 1,
        platforms: {
            myplat: {display_name: "My Platform", version_lines: ["v1"]}
        }
    } | to nuon) | save --force ($tmp | path join "config/matrix/platforms.nuon")
    let err = (try {
        build-matrix-rules-json {scenarios: {}} "config/matrix" {} {} $tmp
    } catch {|e| $e.msg})
    let result = [
        (assert-string-contains $err "platform 'myplat' is missing required keys" "error names platform and problem")
        (assert-string-contains $err "slug" "error lists missing field slug")
        (assert-string-contains $err "config/matrix" "error includes rules_path")
    ]
    rm --recursive --force $tmp
    $result
}

def test-build-matrix-rules-json-rejects-empty-version-lines [] {
    test-log "\n[test-build-matrix-rules-json-rejects-empty-version-lines]"
    mut tmp = ($nu.temp-path | path join $"ocmts-emptylines-(random uuid)")
    mkdir $tmp
    materialize-provenance-stubs $tmp
    # Platform with all keys present but version_lines is an empty list.
    ({
        schema_version: 1,
        platforms: {
            myplat: {slug: "mp", display_name: "My Platform", version_lines: []}
        }
    } | to nuon) | save --force ($tmp | path join "config/matrix/platforms.nuon")
    let err = (try {
        build-matrix-rules-json {scenarios: {}} "config/matrix" {} {} $tmp
    } catch {|e| $e.msg})
    # Same validation must reject scalar values too.
    ({
        schema_version: 1,
        platforms: {
            myplat: {slug: "mp", display_name: "My Platform", version_lines: "v1"}
        }
    } | to nuon) | save --force ($tmp | path join "config/matrix/platforms.nuon")
    let scalar_err = (try {
        build-matrix-rules-json {scenarios: {}} "config/matrix" {} {} $tmp
    } catch {|e| $e.msg})
    let result = [
        (assert-string-contains $err "platform 'myplat' version_lines must be a non-empty list" "error names platform and requirement")
        (assert-string-contains $err "config/matrix" "error includes rules_path")
        (assert-string-contains $scalar_err "platform 'myplat' version_lines must be a non-empty list" "scalar version_lines rejected with same error")
        (assert-string-contains $scalar_err "config/matrix" "scalar error includes rules_path")
    ]
    rm --recursive --force $tmp
    $result
}

def test-build-matrix-rules-json-stable-platform-sort [] {
    test-log "\n[test-build-matrix-rules-json-stable-platform-sort]"
    mut tmp = ($nu.temp-path | path join $"ocmts-platsort-(random uuid)")
    mkdir $tmp
    materialize-provenance-stubs $tmp
    fill-flow-stubs $tmp
    # Two platforms sharing a display_name; id must break the tie.
    ({
        schema_version: 1,
        platforms: {
            zzz_plat: {slug: "z", display_name: "Tied Name", version_lines: ["v1"]},
            aaa_plat: {slug: "a", display_name: "Tied Name", version_lines: ["v1"]},
            beta:     {slug: "b", display_name: "Alpha",     version_lines: ["v2"]},
        }
    } | to nuon) | save --force ($tmp | path join "config/matrix/platforms.nuon")
    let out = (build-matrix-rules-json {scenarios: {}} "config/matrix" {} {} $tmp)
    let plat_ids = ($out.platforms | each {|p| $p.id})
    let result = [
        (assert-eq $plat_ids ["beta" "aaa_plat" "zzz_plat"]
            "platforms sorted by display_name then id as tie-break")
    ]
    rm --recursive --force $tmp
    $result
}

def test-gate-cells-by-capabilities-locked-mapping [] {
    test-log "\n[test-gate-cells-by-capabilities-locked-mapping]"
    # Verify the locked status->action/display_visible/display_status mapping via
    # gate-cells-by-capabilities. One cell per status scenario.
    let flow_caps = {
        "f": {sender: ["cap.f.sender"], receiver: []},
    }
    def cell-for [s: string, platform: string] {
        {
            cell_id: $"f__($platform)-v1",
            flow_id: "f",
            scenario: "f",
            sender_platform: $platform,
            sender_version: "v1",
            receiver_platform: "",
            receiver_version: "",
            is_two_party: false,
            enabled: true,
            browser: "chrome",
        }
    }
    let adapters = {
        "supported/v1": {capabilities: {"cap.f.sender": {status: "supported"}}},
        "test-pending/v1": {capabilities: {"cap.f.sender": {status: "test-implementation-pending"}}},
        "vendor-unsupported/v1": {capabilities: {"cap.f.sender": {status: "vendor-unsupported"}}},
        "oos/v1": {capabilities: {"cap.f.sender": {status: "vendor-out-of-scope"}}},
    }
    let cells = [
        (cell-for "supported" "supported")
        (cell-for "test-pending" "test-pending")
        (cell-for "vendor-unsupported" "vendor-unsupported")
        (cell-for "oos" "oos")
    ]
    let gated = (gate-cells-by-capabilities $cells $adapters $flow_caps)
    let by_plat = ($gated | reduce --fold {} {|c, acc|
        $acc | upsert $c.sender_platform $c
    })
    [
        (assert-eq ($by_plat | get supported | get capability_action) "run"
            "supported -> action run")
        (assert-truthy ($by_plat | get supported | get display_visible)
            "supported -> display_visible true")
        (assert-eq ($by_plat | get supported | get display_status) "supported"
            "supported -> display_status supported")

        (assert-eq ($by_plat | get test-pending | get capability_action) "capability-skipped"
            "test-implementation-pending -> action capability-skipped")
        (assert-truthy ($by_plat | get test-pending | get display_visible)
            "test-implementation-pending -> display_visible true")
        (assert-eq ($by_plat | get test-pending | get display_status) "test-pending"
            "test-implementation-pending -> display_status test-pending")

        (assert-eq ($by_plat | get vendor-unsupported | get capability_action) "exclude-placeholder"
            "vendor-unsupported -> action exclude-placeholder")
        (assert-truthy ($by_plat | get vendor-unsupported | get display_visible)
            "vendor-unsupported -> display_visible true")
        (assert-eq ($by_plat | get vendor-unsupported | get display_status) "vendor-unsupported"
            "vendor-unsupported -> display_status vendor-unsupported")

        (assert-eq ($by_plat | get oos | get capability_action) "exclude-placeholder"
            "vendor-out-of-scope -> action exclude-placeholder")
        (assert-truthy (not ($by_plat | get oos | get display_visible))
            "vendor-out-of-scope -> display_visible false")
        (assert-eq ($by_plat | get oos | get display_status) "out-of-scope"
            "vendor-out-of-scope -> display_status out-of-scope")
    ]
}

# Disabled+supported version (placeholder) coexists with a fully supported version.
# Both must appear in kept_cells with the correct display_status each.
def test-apply-display-rule-placeholder-coexists-with-supported [] {
    test-log "\n[test-apply-display-rule-placeholder-coexists-with-supported]"
    let adapters = {
        "nextcloud/v32": {
            capabilities: {
                "op.login": {status: "supported"},
                "flow.share-with.sender": {status: "supported"},
                "flow.share-with.receiver": {status: "supported"},
                "op.share-file.sender": {status: "supported"},
                "op.share-file.receiver": {status: "supported"},
            }
        },
        "nextcloud/v34": {
            capabilities: {
                "op.login": {status: "supported"},
                "flow.share-with.sender": {status: "supported"},
                "flow.share-with.receiver": {status: "supported"},
                "op.share-file.sender": {status: "supported"},
                "op.share-file.receiver": {status: "supported"},
            }
        },
    }
    let cells = [
        (make-cell --sender_version "v32" --receiver_platform "nextcloud" --receiver_version "v32" --enabled false)
        (make-cell --sender_version "v34" --receiver_platform "nextcloud" --receiver_version "v34")
    ]
    let result = (apply-display-rule $cells $adapters (fixture-share-with-flow-caps))
    let kept_versions = ($result.kept_cells | each {|c| $c.sender_version} | sort)
    let v32_cells = ($result.kept_cells | where {|c| $c.sender_version == "v32"})
    let v34_cells = ($result.kept_cells | where {|c| $c.sender_version == "v34"})
    [
        (assert-eq $kept_versions ["v32" "v34"]
            "both placeholder v32 and supported v34 appear in kept_cells")
        (assert-truthy (not ($v32_cells | is-empty))
            "v32 placeholder cell is present in kept_cells")
        (assert-eq ($v32_cells | first | get display_status) "placeholder"
            "disabled v32 has display_status placeholder")
        (assert-truthy (not ($v34_cells | is-empty))
            "v34 supported cell is present in kept_cells")
        (assert-eq ($v34_cells | first | get display_status) "supported"
            "enabled v34 has display_status supported")
    ]
}

# Vendor-unsupported version remains visible alongside a placeholder version.
# When no supported or test-pending exist, vendor-unsupported (last) is picked
# and all placeholder versions are always included alongside it.
def test-apply-display-rule-vendor-unsupported-remains-alongside-placeholder [] {
    test-log "\n[test-apply-display-rule-vendor-unsupported-remains-alongside-placeholder]"
    let adapters = {
        "nextcloud/v32": {
            capabilities: {
                "op.login": {status: "supported"},
                "flow.share-with.sender": {status: "supported"},
                "flow.share-with.receiver": {status: "supported"},
                "op.share-file.sender": {status: "supported"},
                "op.share-file.receiver": {status: "supported"},
            }
        },
        "nextcloud/v33": {
            capabilities: {
                "op.login": {status: "supported"},
                "flow.share-with.sender": {status: "vendor-unsupported"},
                "flow.share-with.receiver": {status: "vendor-unsupported"},
                "op.share-file.sender": {status: "supported"},
                "op.share-file.receiver": {status: "supported"},
            }
        },
    }
    let cells = [
        (make-cell --sender_version "v32" --receiver_platform "nextcloud" --receiver_version "v32" --enabled false)
        (make-cell --sender_version "v33" --receiver_platform "nextcloud" --receiver_version "v33")
    ]
    let result = (apply-display-rule $cells $adapters (fixture-share-with-flow-caps))
    let kept_versions = ($result.kept_cells | each {|c| $c.sender_version} | sort)
    let v33_cells = ($result.kept_cells | where {|c| $c.sender_version == "v33"})
    [
        (assert-truthy (not ($v33_cells | is-empty))
            "vendor-unsupported v33 remains in kept_cells")
        (assert-eq ($v33_cells | first | get display_status) "vendor-unsupported"
            "v33 display_status is vendor-unsupported")
        (assert-eq ($result.not_in_scope | length) 0
            "vendor-unsupported v33 does not land in not_in_scope")
        (assert-truthy ("v32" in $kept_versions)
            "placeholder v32 also appears in kept_cells")
    ]
}

def main [] {
    test-log "=== matrix rules-gen tests ==="
    let results = (
        (test-apply-display-rule-keeps-supported-only)
        | append (test-apply-display-rule-keeps-latest-test-pending)
        | append (test-apply-display-rule-emits-not-in-scope)
        | append (test-build-matrix-rules-json-includes-display-status)
        | append (test-build-matrix-not-in-scope-json-shape)
        | append (test-build-matrix-rules-json-provenance-shape)
        | append (test-expand-flow-skips-disabled-flow)
        | append (test-build-matrix-rules-json-emits-flows-and-platforms)
        | append (test-build-matrix-rules-json-rejects-empty-flows-dir)
        | append (test-build-matrix-rules-json-rejects-missing-platforms)
        | append (test-build-matrix-rules-json-rejects-platform-missing-keys)
        | append (test-build-matrix-rules-json-rejects-empty-version-lines)
        | append (test-build-matrix-rules-json-stable-platform-sort)
        | append (test-gate-cells-by-capabilities-locked-mapping)
        | append (test-apply-display-rule-placeholder-coexists-with-supported)
        | append (test-apply-display-rule-vendor-unsupported-remains-alongside-placeholder)
    ) | flatten
    run-suite "site/rules-gen" $SUITE_PATH $results
}
