# Shared CI test fixtures reused across CI suite files.
# Support module only: no `main`; imported by ci/*.nu suites.

use ../../lib/ci/planner.nu [plan-suite]
use ../../lib/matrix/rules-gen.nu [load-matrix-rules]
use ../../lib/site/flow-caps.nu [load-flow-caps]

const FIXTURES_PATH = path self

def ci-fixture-repo-root [] {
    $FIXTURES_PATH | path dirname | path join ".." ".." ".." | path expand
}

# Production CI plan from real matrix rules, prerequisites, flow-caps, adapters.
export def prod-plan [] {
    let repo_root = (ci-fixture-repo-root)
    let rules = (load-matrix-rules $repo_root)
    let prod_prereqs = (open ($repo_root | path join "config" "ci" "prerequisites.nuon"))
    let flow_caps = (load-flow-caps ($repo_root | path join "config" "matrix" "flows"))
    let adapters = (open ($repo_root | path join "config" "adapters" "capabilities.v1.nuon") | get adapters)
    let plan = (plan-suite $rules $prod_prereqs $flow_caps $adapters)
    {repo_root: $repo_root, plan: $plan}
}

export def fixture-rules [] {
    {
        matrix: {
            login__nextcloud: {
                enabled: true,
                flow_id: "login",
                browsers: ["chrome"],
                sender: {platform: "nextcloud", version_lines: ["v33" "v34"]},
                receiver: null,
                mitm: false,
            },
            share-with__nextcloud__nextcloud: {
                enabled: true,
                flow_id: "share-with",
                browsers: ["chrome"],
                sender: {platform: "nextcloud", version_lines: ["v34"]},
                receiver: {platform: "nextcloud", version_lines: ["v34"]},
                mitm: true,
            },
            login__ocmgo: {
                enabled: false,
                flow_id: "login",
                browsers: ["chrome"],
                sender: {platform: "ocmgo", version_lines: ["v1"]},
                receiver: null,
                mitm: false,
            },
        }
    }
}

export def fixture-prereqs [] {
    {
        capability_rules: [
            {
                capability_flow: "login",
                required_for_flows: ["share-with" "contact-token" "contact-wayf"],
                required_roles: ["sender" "receiver"],
            }
        ]
    }
}

export def fixture-flow-caps [] {
    {
        "login": {sender: [], receiver: []},
        "share-with": {sender: [], receiver: []},
    }
}

export def fixture-rules-cap-tests [] {
    {
        matrix: {
            login__nextcloud: {
                enabled: true,
                flow_id: "login",
                browsers: ["chrome"],
                sender: {platform: "nextcloud", version_lines: ["v34"]},
                receiver: null,
                mitm: false,
            },
            login__opencloud: {
                enabled: true,
                flow_id: "login",
                browsers: ["chrome"],
                sender: {platform: "opencloud", version_lines: ["v6"]},
                receiver: null,
                mitm: false,
            },
        }
    }
}

export def fixture-flow-caps-with-reqs [] {
    {
        "login": {
            sender: ["flow.login.sender"],
            receiver: [],
        }
    }
}

export def fixture-adapters-cap [] {
    {
        "nextcloud/v34": {
            capabilities: {
                "flow.login.sender": {status: "supported"},
            }
        },
        "opencloud/v6": {
            capabilities: {
                "flow.login.sender": {status: "test-implementation-pending"},
            }
        },
    }
}

export def fixture-rules-only-cap-skipped [] {
    {
        matrix: {
            login__opencloud: {
                enabled: true,
                flow_id: "login",
                browsers: ["chrome"],
                sender: {platform: "opencloud", version_lines: ["v6"]},
                receiver: null,
                mitm: false,
            },
        }
    }
}

# Add glyph_id to flow stubs from materialize-provenance-stubs for publish validation.
export def patch-flow-glyph-ids [tmp_root: string]: nothing -> nothing {
    let flows_dir = ($tmp_root | path join "config/matrix/flows")
    let webapp_path = ($flows_dir | path join "webapp-share.nuon")
    if not ($webapp_path | path exists) {
        ({
            flow_id: "webapp-share",
            label: "Webapp Share",
            subtitle: "Share from sender webapp to receiver",
            glyph_id: "app-window",
            display_order: 30,
            enabled: false,
            two_party: true,
            mitm: true,
            required_capabilities: {sender: [], receiver: []},
        } | to nuon) | save --force $webapp_path
    }
    let glyphs = {
        contact-token: "ticket",
        contact-wayf: "compass",
        login: "key",
        share-with: "share-2",
        webapp-share: "app-window",
    }
    for stem_glyph in ($glyphs | transpose stem glyph_id) {
        let path = ($flows_dir | path join $"($stem_glyph.stem).nuon")
        if ($path | path exists) {
            open $path
            | upsert glyph_id $stem_glyph.glyph_id
            | to nuon
            | save --force $path
        }
    }
}
