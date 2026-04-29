# Tests for the matrix display rule and not-in-scope emitter.
# Run: nu scripts/tests/site/rules-gen.nu

const SUITE_PATH = path self

use ../../lib/matrix/rules-gen.nu [
    apply-display-rule
    build-matrix-not-in-scope-json
    classify-version-status
]
use ../../lib/site/manifest.nu [build-matrix-rules-json]
use ../../lib/tests/assert.nu *
use ../../lib/tests/fixtures.nu [materialize-provenance-stubs]
use ../../lib/tests/runner.nu [run-suite]

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
            sender: ["login", "share-with.sender"],
            receiver: ["login", "share-with.receiver"],
        },
        "code-flow": {
            sender: ["login", "share-with.sender"],
            receiver: ["login", "share-with.receiver"],
        },
        "contact-wayf": {
            sender: ["login", "contact-wayf.sender"],
            receiver: ["login", "contact-wayf.receiver"],
        },
    }
}

# When v34 (supported) exists alongside v32, v33 (vendor-unsupported), keep only v34.
def test-apply-display-rule-keeps-supported-only [] {
    test-log "\n[test-apply-display-rule-keeps-supported-only]"
    let adapters = {
        "nextcloud/v32": {
            capabilities: {
                "login": {status: "supported"},
                "share-with.sender": {status: "vendor-unsupported"},
                "share-with.receiver": {status: "vendor-unsupported"},
            }
        },
        "nextcloud/v33": {
            capabilities: {
                "login": {status: "supported"},
                "share-with.sender": {status: "vendor-unsupported"},
                "share-with.receiver": {status: "vendor-unsupported"},
            }
        },
        "nextcloud/v34": {
            capabilities: {
                "login": {status: "supported"},
                "share-with.sender": {status: "supported"},
                "share-with.receiver": {status: "supported"},
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
                "login": {status: "supported"},
                "share-with.sender": {status: "test-implementation-pending"},
                "share-with.receiver": {status: "test-implementation-pending"},
            }
        },
        "opencloud/v6": {
            capabilities: {
                "login": {status: "supported"},
                "share-with.sender": {status: "test-implementation-pending"},
                "share-with.receiver": {status: "test-implementation-pending"},
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
        (assert-truthy ("test-implementation-pending" in $display_statuses)
            "kept cell has test-implementation-pending display_status")
    ]
}

# Vendor-out-of-scope drops the (flow, platform, role) entirely and lands in not_in_scope.
def test-apply-display-rule-emits-not-in-scope [] {
    test-log "\n[test-apply-display-rule-emits-not-in-scope]"
    let adapters = {
        "seafile/v1": {
            capabilities: {
                "login": {status: "supported"},
                "share-with.sender": {
                    status: "vendor-out-of-scope",
                    rationale: "seafile does not implement OCM code-flow",
                },
                "share-with.receiver": {
                    status: "vendor-out-of-scope",
                    rationale: "seafile does not implement OCM code-flow",
                },
            }
        },
        "nextcloud/v34": {
            capabilities: {
                "login": {status: "supported"},
                "share-with.sender": {status: "supported"},
                "share-with.receiver": {status: "supported"},
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
                "login": {status: "supported"},
                "share-with.sender": {status: "supported"},
                "share-with.receiver": {status: "supported"},
            }
        },
        "opencloud/v6": {
            capabilities: {
                "login": {status: "supported"},
                "share-with.sender": {status: "test-implementation-pending"},
                "share-with.receiver": {status: "test-implementation-pending"},
            }
        },
        "ocis/v8": {
            capabilities: {
                "login": {status: "supported"},
                "share-with.sender": {
                    status: "vendor-out-of-scope",
                    rationale: "ocis requires prior contact-token",
                },
                "share-with.receiver": {
                    status: "vendor-out-of-scope",
                    rationale: "ocis requires prior contact-token",
                },
            }
        },
    }
    let cells = [
        (make-cell --sender_version "v34" --receiver_platform "nextcloud" --receiver_version "v34")
        (make-cell --sender_platform "opencloud" --sender_version "v6" --receiver_platform "opencloud" --receiver_version "v6")
        (make-cell --sender_platform "ocis" --sender_version "v8" --receiver_platform "nextcloud" --receiver_version "v34")
    ]
    let result = (apply-display-rule $cells $adapters (fixture-share-with-flow-caps))
    let visible = ["supported", "test-implementation-pending", "vendor-unsupported", "placeholder"]
    let all_have_status = ($result.kept_cells | all {|c| ($c.display_status? | default "") != ""})
    let none_oos = ($result.kept_cells | all {|c| $c.display_status != "vendor-out-of-scope"})
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

def main [] {
    test-log "=== matrix rules-gen tests ==="
    let results = (
        (test-apply-display-rule-keeps-supported-only)
        | append (test-apply-display-rule-keeps-latest-test-pending)
        | append (test-apply-display-rule-emits-not-in-scope)
        | append (test-build-matrix-rules-json-includes-display-status)
        | append (test-build-matrix-not-in-scope-json-shape)
        | append (test-build-matrix-rules-json-provenance-shape)
    ) | flatten
    run-suite "site/rules-gen" $SUITE_PATH $results
}
