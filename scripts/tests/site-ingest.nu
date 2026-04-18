# derive-cell-impl-info gating tests for site-ingest.nu.
# Run: nu scripts/tests/site-ingest.nu
# Returns exit 0 on all pass, exit 1 with details on failure.

use ../lib/site-ingest.nu [derive-cell-impl-info]

def PASS [] { "PASS" }
def FAIL [msg: string] { $"FAIL: ($msg)" }

def assert-eq [got: any, want: any, label: string] {
    if $got == $want {
        print $"  ok: ($label)"
        PASS
    } else {
        print $"  FAIL: ($label)"
        print $"    got:  ($got | to json)"
        print $"    want: ($want | to json)"
        FAIL $label
    }
}

def assert-truthy [got: bool, label: string] {
    if $got {
        print $"  ok: ($label)"
        PASS
    } else {
        print $"  FAIL: ($label) - expected true"
        FAIL $label
    }
}

# Adapter map covering all capability names used in tests.
def fixture-adapters [] {
    {
        "nextcloud/v34": [
            "login",
            "share-with.sender",
            "share-with.receiver",
            "contact-token.sender",
            "contact-token.receiver",
            "contact-wayf.sender",
            "contact-wayf.receiver",
            "provider-identity",
        ],
        # v33 has only the share-with caps, no contact-* or provider-identity.
        "nextcloud/v33": [
            "login",
            "share-with.sender",
            "share-with.receiver",
        ],
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

# login: only requires login cap; no receiver caps.
def test-login-implemented [] {
    print "\n[test-login-implemented]"
    let adapters = fixture-adapters
    let cell = (make-one-party-cell "login" "nextcloud" "v34")
    let info = (derive-cell-impl-info $cell $adapters)
    let req_caps = ($info.requirements | each {|r| $r.capability})
    [
        (assert-eq $req_caps ["login"] "login flow requires only login cap")
        (assert-truthy ($info.blockers | is-empty) "login/v34 has no blockers")
    ]
}

# share-with: sender needs login+share-with.sender; receiver needs
# login+share-with.receiver. Behavior must be unchanged after the fix.
def test-share-with-implemented [] {
    print "\n[test-share-with-implemented]"
    let adapters = fixture-adapters
    let cell = (make-two-party-cell "share-with"
        "nextcloud" "v34" "nextcloud" "v34")
    let info = (derive-cell-impl-info $cell $adapters)
    let sender_caps = ($info.requirements | where role == "sender" | each {|r| $r.capability})
    let receiver_caps = ($info.requirements | where role == "receiver" | each {|r| $r.capability})
    [
        (assert-eq $sender_caps ["login", "share-with.sender"]
            "share-with sender requires login + share-with.sender")
        (assert-eq $receiver_caps ["login", "share-with.receiver"]
            "share-with receiver requires login + share-with.receiver")
        (assert-truthy ($info.blockers | is-empty)
            "share-with/v34 has no blockers")
    ]
}

# share-with on v33 (which has share-with caps) must also be implemented.
def test-share-with-v33-implemented [] {
    print "\n[test-share-with-v33-implemented]"
    let adapters = fixture-adapters
    let cell = (make-two-party-cell "share-with"
        "nextcloud" "v33" "nextcloud" "v33")
    let info = (derive-cell-impl-info $cell $adapters)
    [
        (assert-truthy ($info.blockers | is-empty)
            "share-with/v33 has no blockers")
    ]
}

# contact-token: sender needs login+contact-token.sender+share-with.sender;
# receiver needs login+contact-token.receiver+provider-identity+share-with.receiver.
# v34 has all caps.
def test-contact-token-implemented [] {
    print "\n[test-contact-token-implemented]"
    let adapters = fixture-adapters
    let cell = (make-two-party-cell "contact-token"
        "nextcloud" "v34" "nextcloud" "v34")
    let info = (derive-cell-impl-info $cell $adapters)
    let sender_caps = ($info.requirements | where role == "sender" | each {|r| $r.capability})
    let receiver_caps = ($info.requirements | where role == "receiver" | each {|r| $r.capability})
    [
        (assert-eq $sender_caps ["login", "contact-token.sender", "share-with.sender"]
            "contact-token sender requires login + contact-token.sender + share-with.sender")
        (assert-eq $receiver_caps ["login", "contact-token.receiver", "provider-identity", "share-with.receiver"]
            "contact-token receiver requires login + contact-token.receiver + provider-identity + share-with.receiver")
        (assert-truthy ($info.blockers | is-empty)
            "contact-token/v34 has no blockers")
    ]
}

# contact-token on v33 must be blocked: v33 lacks contact-token.sender,
# contact-token.receiver, and provider-identity.
def test-contact-token-v33-blocked [] {
    print "\n[test-contact-token-v33-blocked]"
    let adapters = fixture-adapters
    let cell = (make-two-party-cell "contact-token"
        "nextcloud" "v33" "nextcloud" "v33")
    let info = (derive-cell-impl-info $cell $adapters)
    let blocker_caps = ($info.blockers | where reason_code == "missing_capability" | each {|b| $b.capability})
    [
        (assert-truthy (not ($info.blockers | is-empty))
            "contact-token/v33 has blockers")
        (assert-truthy ("contact-token.sender" in $blocker_caps)
            "contact-token/v33 blocked on contact-token.sender")
        (assert-truthy ("contact-token.receiver" in $blocker_caps)
            "contact-token/v33 blocked on contact-token.receiver")
        (assert-truthy ("provider-identity" in $blocker_caps)
            "contact-token/v33 blocked on provider-identity")
    ]
}

# contact-token resolves senderShareWith/receiverShareWith adapters at runtime,
# so share-with caps must appear in requirements.
def test-contact-token-share-with-required [] {
    print "\n[test-contact-token-share-with-required]"
    let adapters = fixture-adapters
    let cell = (make-two-party-cell "contact-token"
        "nextcloud" "v34" "nextcloud" "v34")
    let info = (derive-cell-impl-info $cell $adapters)
    let all_caps = ($info.requirements | each {|r| $r.capability})
    [
        (assert-truthy ("share-with.sender" in $all_caps)
            "contact-token requires share-with.sender")
        (assert-truthy ("share-with.receiver" in $all_caps)
            "contact-token requires share-with.receiver")
    ]
}

# contact-wayf: sender needs login+contact-wayf.sender+share-with.sender;
# receiver needs login+contact-wayf.receiver+provider-identity+share-with.receiver.
# v34 has all caps.
def test-contact-wayf-implemented [] {
    print "\n[test-contact-wayf-implemented]"
    let adapters = fixture-adapters
    let cell = (make-two-party-cell "contact-wayf"
        "nextcloud" "v34" "nextcloud" "v34")
    let info = (derive-cell-impl-info $cell $adapters)
    let sender_caps = ($info.requirements | where role == "sender" | each {|r| $r.capability})
    let receiver_caps = ($info.requirements | where role == "receiver" | each {|r| $r.capability})
    [
        (assert-eq $sender_caps ["login", "contact-wayf.sender", "share-with.sender"]
            "contact-wayf sender requires login + contact-wayf.sender + share-with.sender")
        (assert-eq $receiver_caps ["login", "contact-wayf.receiver", "provider-identity", "share-with.receiver"]
            "contact-wayf receiver requires login + contact-wayf.receiver + provider-identity + share-with.receiver")
        (assert-truthy ($info.blockers | is-empty)
            "contact-wayf/v34 has no blockers")
    ]
}

# contact-wayf on v33 must be blocked.
def test-contact-wayf-v33-blocked [] {
    print "\n[test-contact-wayf-v33-blocked]"
    let adapters = fixture-adapters
    let cell = (make-two-party-cell "contact-wayf"
        "nextcloud" "v33" "nextcloud" "v33")
    let info = (derive-cell-impl-info $cell $adapters)
    let blocker_caps = ($info.blockers | where reason_code == "missing_capability" | each {|b| $b.capability})
    [
        (assert-truthy (not ($info.blockers | is-empty))
            "contact-wayf/v33 has blockers")
        (assert-truthy ("contact-wayf.sender" in $blocker_caps)
            "contact-wayf/v33 blocked on contact-wayf.sender")
        (assert-truthy ("contact-wayf.receiver" in $blocker_caps)
            "contact-wayf/v33 blocked on contact-wayf.receiver")
        (assert-truthy ("provider-identity" in $blocker_caps)
            "contact-wayf/v33 blocked on provider-identity")
    ]
}

# contact-wayf resolves senderShareWith/receiverShareWith adapters at runtime,
# so share-with caps must appear in requirements.
def test-contact-wayf-share-with-required [] {
    print "\n[test-contact-wayf-share-with-required]"
    let adapters = fixture-adapters
    let cell = (make-two-party-cell "contact-wayf"
        "nextcloud" "v34" "nextcloud" "v34")
    let info = (derive-cell-impl-info $cell $adapters)
    let all_caps = ($info.requirements | each {|r| $r.capability})
    [
        (assert-truthy ("share-with.sender" in $all_caps)
            "contact-wayf requires share-with.sender")
        (assert-truthy ("share-with.receiver" in $all_caps)
            "contact-wayf requires share-with.receiver")
    ]
}

# Unknown flow_id returns an unknown_flow_id blocker.
def test-unknown-flow-id [] {
    print "\n[test-unknown-flow-id]"
    let adapters = fixture-adapters
    let cell = (make-one-party-cell "no-such-flow" "nextcloud" "v34")
    let info = (derive-cell-impl-info $cell $adapters)
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
    print "\n[test-missing-adapter-bundle]"
    let adapters = {}
    let cell = (make-two-party-cell "share-with"
        "nextcloud" "v99" "nextcloud" "v99")
    let info = (derive-cell-impl-info $cell $adapters)
    let blocker_codes = ($info.blockers | each {|b| $b.reason_code})
    [
        (assert-truthy ("missing_adapter_bundle" in $blocker_codes)
            "unknown adapter yields missing_adapter_bundle blocker")
    ]
}

def main [] {
    print "=== site-ingest derive-cell-impl-info Tests ==="
    let results = (
        (test-login-implemented)
        | append (test-share-with-implemented)
        | append (test-share-with-v33-implemented)
        | append (test-contact-token-implemented)
        | append (test-contact-token-v33-blocked)
        | append (test-contact-token-share-with-required)
        | append (test-contact-wayf-implemented)
        | append (test-contact-wayf-v33-blocked)
        | append (test-contact-wayf-share-with-required)
        | append (test-unknown-flow-id)
        | append (test-missing-adapter-bundle)
    )
    let failures = ($results | where {|r| $r != "PASS"})
    let total = ($results | length)
    let passed = ($total - ($failures | length))
    print $"\n=== ($passed)/($total) passed ==="
    if not ($failures | is-empty) {
        print "Failures:"
        for f in $failures { print $"  ($f)" }
        exit 1
    }
    print "All tests passed."
}
