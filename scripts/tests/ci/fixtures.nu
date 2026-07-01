# Shared CI test fixtures reused across CI suite files.
# Support module only: no `main`; imported by ci/*.nu suites.

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
                required_for_flows: ["share-with" "contact-token" "contact-wayf" "code-flow"],
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
