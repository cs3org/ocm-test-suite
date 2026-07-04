# Shared blocker-logic tests (derive-cell-impl-info, worst-status-of-blockers).
# Run: nu scripts/tests/site/blocker-logic.nu
# Returns exit 0 on all pass, exit 1 with details on failure.

const SUITE_PATH = path self

use ../../lib/site/blocker-logic.nu [derive-cell-impl-info worst-status-of-blockers]
use ../../lib/tests/assert.nu *
use ../../lib/tests/runner.nu [run-suite]

# Adapter map covering all capability names used in tests.
# Shape: {adapter_key: {capabilities: {cap_name: {status: ...}}}}.
def fixture-adapters [] {
    {
        "nextcloud/v34": {
            capabilities: {
                "flow.login": {status: "supported"},
                "op.login": {status: "supported"},
                "op.provider-identity": {status: "supported"},
                "flow.share-with.sender": {status: "supported"},
                "flow.share-with.receiver": {status: "supported"},
                "op.share-file.sender": {status: "supported"},
                "op.share-file.receiver": {status: "supported"},
                "flow.contact-token.sender": {status: "supported"},
                "op.contact-token.sender": {status: "supported"},
                "flow.contact-token.receiver": {status: "supported"},
                "op.contact-token.receiver": {status: "supported"},
                "flow.contact-wayf.sender": {status: "supported"},
                "op.contact-wayf.sender": {status: "supported"},
                "flow.contact-wayf.receiver": {status: "supported"},
                "op.contact-wayf.receiver": {status: "supported"},
            }
        },
        # v33 has flow/login, share-with, and share-file caps; contact-* and
        # provider-identity are vendor-unsupported.
        "nextcloud/v33": {
            capabilities: {
                "flow.login": {status: "supported"},
                "op.login": {status: "supported"},
                "op.provider-identity": {status: "vendor-unsupported"},
                "flow.share-with.sender": {status: "supported"},
                "flow.share-with.receiver": {status: "supported"},
                "op.share-file.sender": {status: "supported"},
                "op.share-file.receiver": {status: "supported"},
                "flow.contact-token.sender": {status: "vendor-unsupported"},
                "op.contact-token.sender": {status: "vendor-unsupported"},
                "flow.contact-token.receiver": {status: "vendor-unsupported"},
                "op.contact-token.receiver": {status: "vendor-unsupported"},
                "flow.contact-wayf.sender": {status: "vendor-unsupported"},
                "op.contact-wayf.sender": {status: "vendor-unsupported"},
                "flow.contact-wayf.receiver": {status: "vendor-unsupported"},
                "op.contact-wayf.receiver": {status: "vendor-unsupported"},
            }
        },
    }
}

# Flow capability requirements matching what load-flow-caps would produce.
def fixture-flow-caps [] {
    {
        login: {sender: ["flow.login", "op.login"], receiver: []},
        "share-with": {
            sender: ["flow.share-with.sender", "op.login", "op.share-file.sender"],
            receiver: ["flow.share-with.receiver", "op.login", "op.share-file.receiver"],
        },
        "contact-token": {
            sender: ["flow.contact-token.sender", "op.login", "op.contact-token.sender", "op.share-file.sender"],
            receiver: ["flow.contact-token.receiver", "op.login", "op.contact-token.receiver", "op.provider-identity", "op.share-file.receiver"],
        },
        "contact-wayf": {
            sender: ["flow.contact-wayf.sender", "op.login", "op.contact-wayf.sender", "op.share-file.sender"],
            receiver: ["flow.contact-wayf.receiver", "op.login", "op.contact-wayf.receiver", "op.provider-identity", "op.share-file.receiver"],
        },
    }
}

def make-one-party-cell [flow_id: string, platform: string, version: string] {
    {
        flow_id: $flow_id,
        sender_platform: $platform,
        sender_version: $version,
        is_two_party: false,
        receiver_platform: "",
        receiver_version: "",
    }
}

def make-two-party-cell [
    flow_id: string,
    s_platform: string, s_version: string,
    r_platform: string, r_version: string,
] {
    {
        flow_id: $flow_id,
        sender_platform: $s_platform,
        sender_version: $s_version,
        is_two_party: true,
        receiver_platform: $r_platform,
        receiver_version: $r_version,
    }
}

# login: requires flow.login + op.login; no receiver caps.
def test-login-implemented [] {
    test-log "\n[test-login-implemented]"
    let adapters = fixture-adapters
    let cell = (make-one-party-cell "login" "nextcloud" "v34")
    let info = (derive-cell-impl-info $cell $adapters (fixture-flow-caps))
    let req_caps = ($info.requirements | each {|r| $r.capability})
    [
        (assert-eq $req_caps ["flow.login", "op.login"]
            "login flow requires flow.login + op.login")
        (assert-truthy ($info.blockers | is-empty) "login/v34 has no blockers")
    ]
}

# share-with: sender needs flow.share-with.sender + op.login +
# op.share-file.sender; receiver needs flow.share-with.receiver + op.login +
# op.share-file.receiver.
def test-share-with-implemented [] {
    test-log "\n[test-share-with-implemented]"
    let adapters = fixture-adapters
    let cell = (make-two-party-cell "share-with"
        "nextcloud" "v34" "nextcloud" "v34")
    let info = (derive-cell-impl-info $cell $adapters (fixture-flow-caps))
    let sender_caps = ($info.requirements | where role == "sender" | each {|r| $r.capability})
    let receiver_caps = ($info.requirements | where role == "receiver" | each {|r| $r.capability})
    [
        (assert-eq $sender_caps ["flow.share-with.sender", "op.login", "op.share-file.sender"]
            "share-with sender requires flow.share-with.sender + op.login + op.share-file.sender")
        (assert-eq $receiver_caps ["flow.share-with.receiver", "op.login", "op.share-file.receiver"]
            "share-with receiver requires flow.share-with.receiver + op.login + op.share-file.receiver")
        (assert-truthy ($info.blockers | is-empty)
            "share-with/v34 has no blockers")
    ]
}

# share-with on v33 (which has share-with caps) must also be implemented.
def test-share-with-v33-implemented [] {
    test-log "\n[test-share-with-v33-implemented]"
    let adapters = fixture-adapters
    let cell = (make-two-party-cell "share-with"
        "nextcloud" "v33" "nextcloud" "v33")
    let info = (derive-cell-impl-info $cell $adapters (fixture-flow-caps))
    [
        (assert-truthy ($info.blockers | is-empty)
            "share-with/v33 has no blockers")
    ]
}

# contact-token: sender needs flow.contact-token.sender + op.login +
# op.contact-token.sender + op.share-file.sender; receiver needs
# flow.contact-token.receiver + op.login + op.contact-token.receiver +
# op.provider-identity + op.share-file.receiver.
# v34 has all caps.
def test-contact-token-implemented [] {
    test-log "\n[test-contact-token-implemented]"
    let adapters = fixture-adapters
    let cell = (make-two-party-cell "contact-token"
        "nextcloud" "v34" "nextcloud" "v34")
    let info = (derive-cell-impl-info $cell $adapters (fixture-flow-caps))
    let sender_caps = ($info.requirements | where role == "sender" | each {|r| $r.capability})
    let receiver_caps = ($info.requirements | where role == "receiver" | each {|r| $r.capability})
    [
        (assert-eq $sender_caps ["flow.contact-token.sender", "op.login", "op.contact-token.sender", "op.share-file.sender"]
            "contact-token sender requires flow.contact-token.sender + op.login + op.contact-token.sender + op.share-file.sender")
        (assert-eq $receiver_caps ["flow.contact-token.receiver", "op.login", "op.contact-token.receiver", "op.provider-identity", "op.share-file.receiver"]
            "contact-token receiver requires flow.contact-token.receiver + op.login + op.contact-token.receiver + op.provider-identity + op.share-file.receiver")
        (assert-truthy ($info.blockers | is-empty)
            "contact-token/v34 has no blockers")
    ]
}

# contact-token on v33 must be blocked: v33 has vendor-unsupported for
# flow/op.contact-token.sender, flow/op.contact-token.receiver, and op.provider-identity.
def test-contact-token-v33-blocked [] {
    test-log "\n[test-contact-token-v33-blocked]"
    let adapters = fixture-adapters
    let cell = (make-two-party-cell "contact-token"
        "nextcloud" "v33" "nextcloud" "v33")
    let info = (derive-cell-impl-info $cell $adapters (fixture-flow-caps))
    let blocker_caps = ($info.blockers | where reason_code == "vendor_unsupported" | each {|b| $b.capability})
    [
        (assert-truthy (not ($info.blockers | is-empty))
            "contact-token/v33 has blockers")
        (assert-truthy ("flow.contact-token.sender" in $blocker_caps)
            "contact-token/v33 blocked on flow.contact-token.sender")
        (assert-truthy ("op.contact-token.receiver" in $blocker_caps)
            "contact-token/v33 blocked on op.contact-token.receiver")
        (assert-truthy ("op.provider-identity" in $blocker_caps)
            "contact-token/v33 blocked on op.provider-identity")
    ]
}

# contact-token requires op.share-file caps on both sides.
def test-contact-token-share-file-required [] {
    test-log "\n[test-contact-token-share-file-required]"
    let adapters = fixture-adapters
    let cell = (make-two-party-cell "contact-token"
        "nextcloud" "v34" "nextcloud" "v34")
    let info = (derive-cell-impl-info $cell $adapters (fixture-flow-caps))
    let all_caps = ($info.requirements | each {|r| $r.capability})
    [
        (assert-truthy ("op.share-file.sender" in $all_caps)
            "contact-token requires op.share-file.sender")
        (assert-truthy ("op.share-file.receiver" in $all_caps)
            "contact-token requires op.share-file.receiver")
    ]
}

# contact-wayf: sender needs flow.contact-wayf.sender + op.login +
# op.contact-wayf.sender + op.share-file.sender; receiver needs
# flow.contact-wayf.receiver + op.login + op.contact-wayf.receiver +
# op.provider-identity + op.share-file.receiver.
# v34 has all caps.
def test-contact-wayf-implemented [] {
    test-log "\n[test-contact-wayf-implemented]"
    let adapters = fixture-adapters
    let cell = (make-two-party-cell "contact-wayf"
        "nextcloud" "v34" "nextcloud" "v34")
    let info = (derive-cell-impl-info $cell $adapters (fixture-flow-caps))
    let sender_caps = ($info.requirements | where role == "sender" | each {|r| $r.capability})
    let receiver_caps = ($info.requirements | where role == "receiver" | each {|r| $r.capability})
    [
        (assert-eq $sender_caps ["flow.contact-wayf.sender", "op.login", "op.contact-wayf.sender", "op.share-file.sender"]
            "contact-wayf sender requires flow.contact-wayf.sender + op.login + op.contact-wayf.sender + op.share-file.sender")
        (assert-eq $receiver_caps ["flow.contact-wayf.receiver", "op.login", "op.contact-wayf.receiver", "op.provider-identity", "op.share-file.receiver"]
            "contact-wayf receiver requires flow.contact-wayf.receiver + op.login + op.contact-wayf.receiver + op.provider-identity + op.share-file.receiver")
        (assert-truthy ($info.blockers | is-empty)
            "contact-wayf/v34 has no blockers")
    ]
}

# contact-wayf on v33 must be blocked.
def test-contact-wayf-v33-blocked [] {
    test-log "\n[test-contact-wayf-v33-blocked]"
    let adapters = fixture-adapters
    let cell = (make-two-party-cell "contact-wayf"
        "nextcloud" "v33" "nextcloud" "v33")
    let info = (derive-cell-impl-info $cell $adapters (fixture-flow-caps))
    let blocker_caps = ($info.blockers | where reason_code == "vendor_unsupported" | each {|b| $b.capability})
    [
        (assert-truthy (not ($info.blockers | is-empty))
            "contact-wayf/v33 has blockers")
        (assert-truthy ("flow.contact-wayf.sender" in $blocker_caps)
            "contact-wayf/v33 blocked on flow.contact-wayf.sender")
        (assert-truthy ("op.contact-wayf.receiver" in $blocker_caps)
            "contact-wayf/v33 blocked on op.contact-wayf.receiver")
        (assert-truthy ("op.provider-identity" in $blocker_caps)
            "contact-wayf/v33 blocked on op.provider-identity")
    ]
}

# contact-wayf requires op.share-file caps on both sides.
def test-contact-wayf-share-file-required [] {
    test-log "\n[test-contact-wayf-share-file-required]"
    let adapters = fixture-adapters
    let cell = (make-two-party-cell "contact-wayf"
        "nextcloud" "v34" "nextcloud" "v34")
    let info = (derive-cell-impl-info $cell $adapters (fixture-flow-caps))
    let all_caps = ($info.requirements | each {|r| $r.capability})
    [
        (assert-truthy ("op.share-file.sender" in $all_caps)
            "contact-wayf requires op.share-file.sender")
        (assert-truthy ("op.share-file.receiver" in $all_caps)
            "contact-wayf requires op.share-file.receiver")
    ]
}

# Unknown flow_id returns an unknown_flow_id blocker.
def test-unknown-flow-id [] {
    test-log "\n[test-unknown-flow-id]"
    let adapters = fixture-adapters
    let cell = (make-one-party-cell "no-such-flow" "nextcloud" "v34")
    let info = (derive-cell-impl-info $cell $adapters (fixture-flow-caps))
    let blocker_codes = ($info.blockers | each {|b| $b.reason_code})
    [
        (assert-truthy ("unknown_flow_id" in $blocker_codes)
            "unknown flow_id yields unknown_flow_id blocker")
        (assert-truthy ($info.requirements | is-empty)
            "unknown flow_id yields empty requirements")
    ]
}

# Missing adapter bundle: sender key not in adapters.
def test-missing-adapter-bundle [] {
    test-log "\n[test-missing-adapter-bundle]"
    let adapters = {}
    let cell = (make-two-party-cell "share-with"
        "nextcloud" "v99" "nextcloud" "v99")
    let info = (derive-cell-impl-info $cell $adapters (fixture-flow-caps))
    let blocker_codes = ($info.blockers | each {|b| $b.reason_code})
    [
        (assert-truthy ("missing_adapter_bundle" in $blocker_codes)
            "unknown adapter yields missing_adapter_bundle blocker")
    ]
}

# vendor-out-of-scope: sender share-with caps on ocis/v8 are out-of-scope.
# Blocker reason_code must be "vendor_out_of_scope" and the status field must
# carry the original hyphenated value "vendor-out-of-scope".
def test-share-with-v8-ocis-out-of-scope [] {
    test-log "\n[test-share-with-v8-ocis-out-of-scope]"
    let adapters = {
        "ocis/v8": {
            capabilities: {
                "op.login": {status: "supported"},
                "op.share-file.sender": {status: "supported"},
                "flow.share-with.sender": {status: "vendor-out-of-scope"},
                "flow.share-with.receiver": {status: "vendor-out-of-scope"},
            }
        },
        "nextcloud/v34": (fixture-adapters | get "nextcloud/v34"),
    }
    let cell = (make-two-party-cell "share-with" "ocis" "v8" "nextcloud" "v34")
    let info = (derive-cell-impl-info $cell $adapters (fixture-flow-caps))
    let oos_blockers = ($info.blockers | where reason_code == "vendor_out_of_scope")
    let sender_oos = ($oos_blockers | where {|b| ($b.capability == "flow.share-with.sender") and ($b.role == "sender")})
    [
        (assert-truthy (not ($oos_blockers | is-empty))
            "ocis/v8 flow.share-with.sender yields vendor_out_of_scope blocker")
        (assert-truthy (not ($sender_oos | is-empty))
            "vendor_out_of_scope blocker is for flow.share-with.sender sender role")
        (assert-eq ($sender_oos | first | get status) "vendor-out-of-scope"
            "status field uses hyphenated form vendor-out-of-scope")
    ]
}

# test-implementation-pending: ocmgo/v1 has op.contact-token.sender pending.
def test-pending-status [] {
    test-log "\n[test-pending-status]"
    let adapters = {
        "ocmgo/v1": {
            capabilities: {
                "op.login": {status: "supported"},
                "flow.contact-token.sender": {status: "supported"},
                "op.share-file.sender": {status: "supported"},
                "op.contact-token.sender": {status: "test-implementation-pending"},
            }
        },
        "nextcloud/v34": (fixture-adapters | get "nextcloud/v34"),
    }
    let cell = (make-two-party-cell "contact-token" "ocmgo" "v1" "nextcloud" "v34")
    let info = (derive-cell-impl-info $cell $adapters (fixture-flow-caps))
    let pending_blockers = ($info.blockers | where reason_code == "test_implementation_pending")
    let pending_caps = ($pending_blockers | each {|b| $b.capability})
    [
        (assert-truthy (not ($pending_blockers | is-empty))
            "ocmgo/v1 op.contact-token.sender yields test_implementation_pending blocker")
        (assert-truthy ("op.contact-token.sender" in $pending_caps)
            "pending blocker is for op.contact-token.sender")
    ]
}

# missing_capability_entry: adapter bundle present but op.login cap missing.
def test-missing-capability-entry [] {
    test-log "\n[test-missing-capability-entry]"
    let adapters = {
        "nextcloud/v34": {
            capabilities: {
                "flow.login": {status: "supported"},
                # op.login is intentionally absent
                "flow.share-with.sender": {status: "supported"},
            }
        },
    }
    let cell = (make-one-party-cell "login" "nextcloud" "v34")
    let info = (derive-cell-impl-info $cell $adapters (fixture-flow-caps))
    let missing_blockers = ($info.blockers | where reason_code == "missing_capability_entry")
    [
        (assert-truthy (not ($missing_blockers | is-empty))
            "absent op.login entry yields missing_capability_entry blocker")
        (assert-eq ($missing_blockers | first | get capability) "op.login"
            "missing_capability_entry blocker is for op.login capability")
    ]
}

# Tracking fields propagate from adapter capability entries onto blockers.
def test-derive-cell-impl-info-includes-tracking-fields [] {
    test-log "\n[test-derive-cell-impl-info-includes-tracking-fields]"
    let adapters = {
        "opencloud/v6": {
            capabilities: {
                "op.login": {status: "supported"},
                "flow.contact-token.sender": {status: "supported"},
                "op.share-file.sender": {status: "supported"},
                "op.contact-token.sender": {
                    status: "test-implementation-pending",
                    tracking_url: "https://github.com/x/y/issues/1",
                    rationale: "blocked on upstream PR",
                },
            }
        },
        "nextcloud/v34": (fixture-adapters | get "nextcloud/v34"),
    }
    let cell = (make-two-party-cell "contact-token" "opencloud" "v6" "nextcloud" "v34")
    let info = (derive-cell-impl-info $cell $adapters (fixture-flow-caps))
    let target = ($info.blockers | where {|b| ($b.capability == "op.contact-token.sender") and ($b.role == "sender")})
    let hit = ($target | first)
    [
        (assert-truthy (not ($target | is-empty))
            "op.contact-token.sender blocker present")
        (assert-eq ($hit.tracking_url? | default "")
            "https://github.com/x/y/issues/1"
            "tracking_url propagated to blocker")
        (assert-eq ($hit.rationale? | default "")
            "blocked on upstream PR"
            "rationale propagated to blocker")
    ]
}

# worst-status-of-blockers precedence and edge cases.
def test-worst-status-of-blockers [] {
    test-log "\n[test-worst-status-of-blockers]"
    let mix_pending_unsupported = [
        {status: "test-implementation-pending"},
        {status: "vendor-unsupported"},
    ]
    let all_pending = [
        {status: "test-implementation-pending"},
        {status: "test-implementation-pending"},
    ]
    let includes_oos = [
        {status: "vendor-unsupported"},
        {status: "vendor-out-of-scope"},
    ]
    let missing_bundle = [
        {reason_code: "missing_adapter_bundle", role: "sender"},
    ]
    let just_placeholder = [
        {status: "placeholder"},
        {status: "supported"},
    ]
    [
        (assert-eq (worst-status-of-blockers []) "supported"
            "empty blockers => supported")
        (assert-eq (worst-status-of-blockers $mix_pending_unsupported)
            "vendor-unsupported"
            "pending + unsupported => vendor-unsupported")
        (assert-eq (worst-status-of-blockers $all_pending)
            "test-implementation-pending"
            "all pending => test-implementation-pending")
        (assert-eq (worst-status-of-blockers $includes_oos)
            "vendor-out-of-scope"
            "includes out-of-scope => vendor-out-of-scope")
        (assert-eq (worst-status-of-blockers $missing_bundle)
            "vendor-unsupported"
            "missing_adapter_bundle (no status) => vendor-unsupported")
        (assert-eq (worst-status-of-blockers $just_placeholder)
            "placeholder"
            "placeholder + supported => placeholder")
    ]
}

def main [] {
    test-log "=== site/blocker-logic Tests ==="
    let results = (
        (test-login-implemented)
        | append (test-share-with-implemented)
        | append (test-share-with-v33-implemented)
        | append (test-contact-token-implemented)
        | append (test-contact-token-v33-blocked)
        | append (test-contact-token-share-file-required)
        | append (test-contact-wayf-implemented)
        | append (test-contact-wayf-v33-blocked)
        | append (test-contact-wayf-share-file-required)
        | append (test-unknown-flow-id)
        | append (test-missing-adapter-bundle)
        | append (test-share-with-v8-ocis-out-of-scope)
        | append (test-pending-status)
        | append (test-missing-capability-entry)
        | append (test-derive-cell-impl-info-includes-tracking-fields)
        | append (test-worst-status-of-blockers)
    ) | flatten
    run-suite "site/blocker-logic" $SUITE_PATH $results
}
