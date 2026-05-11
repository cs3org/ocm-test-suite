# Shared CI test fixtures reused across CI suite files.
# The core triad (rules/prereqs/flow-caps) is used by planner, aggregate,
# workflow-gen, workflow-assets, workflow-contract, run-cell-media, and
# site-reusable-workflow. The capability-specific fixtures (rules-cap-tests,
# flow-caps-with-reqs, adapters-cap) are shared between capability-plan and
# capability-artifacts.

# Minimal matrix rules fixture covering key cases.
# Four scenarios: login (v33+v34), login-v34-only, share-with, disabled-flow.
export def fixture-rules [] {
    {
        scenarios: {
            login: {
                enabled: true,
                flow_id: "login",
                browsers: ["chrome"],
                sender: {platform: "nextcloud", version_lines: ["v33" "v34"]},
                receiver: null,
                mitm: false,
            },
            "login-v34-only": {
                enabled: true,
                flow_id: "login",
                browsers: ["chrome"],
                sender: {platform: "nextcloud", version_lines: ["v34"]},
                receiver: null,
                mitm: false,
            },
            "share-with": {
                enabled: true,
                flow_id: "share-with",
                browsers: ["chrome"],
                sender: {platform: "nextcloud", version_lines: ["v34"]},
                receiver: {platform: "nextcloud", version_lines: ["v34"]},
                mitm: true,
            },
            "disabled-flow": {
                enabled: false,
                flow_id: "login",
                browsers: ["chrome"],
                sender: {platform: "nextcloud", version_lines: ["v33"]},
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
                required_for_flows: ["share-with" "contact-token" "contact-wayf" "code-flow"],
                required_roles: ["sender" "receiver"],
            }
        ]
    }
}

# Flow caps with no capability requirements (empty sender/receiver lists).
# Every enabled cell comes out as "supported" / capability_action "run".
export def fixture-flow-caps [] {
    {
        "login": {sender: [], receiver: []},
        "share-with": {sender: [], receiver: []},
    }
}

# Rules fixture for capability gating tests: nextcloud-v34 (supported) and
# opencloud-v6 (test-implementation-pending).
export def fixture-rules-cap-tests [] {
    {
        scenarios: {
            "login-nc": {
                enabled: true,
                flow_id: "login",
                browsers: ["chrome"],
                sender: {platform: "nextcloud", version_lines: ["v34"]},
                receiver: null,
                mitm: false,
            },
            "login-oc": {
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

# Flow caps that require the flow.login.sender capability.
export def fixture-flow-caps-with-reqs [] {
    {
        "login": {
            sender: ["flow.login.sender"],
            receiver: [],
        }
    }
}

# Adapter capability map: nextcloud/v34 is supported, opencloud/v6 is pending.
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

# Rules where ONLY a capability-skipped cell exists in a flow,
# to test that flows with zero runnable cells are omitted from assets/yml.
export def fixture-rules-only-cap-skipped [] {
    {
        scenarios: {
            "login-oc-only": {
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
