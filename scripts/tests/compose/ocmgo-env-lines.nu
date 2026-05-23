# Unit tests for ocmgo-env-lines in scripts/lib/compose/topology-common.nu.
# Covers the route env contract (T6b): two-party ocmgo sender/receiver, one-party
# ocmgo (no peer), and non-ocmgo platforms (all slots blank).
# Run: nu scripts/tests/compose/ocmgo-env-lines.nu

const SUITE_PATH = path self

use ../../lib/compose/topology-common.nu [ocmgo-env-lines]
use ../../lib/tests/assert.nu *
use ../../lib/tests/runner.nu [run-suite]

# Minimal actor fixture for ocmgo tests.
def fixture-actor [] {
    {username: "admin", password: "secret", platform: "ocmgo"}
}

# Two-party ocmgo sender: ROUTE_PEER_HOSTS equals receiver short host.
def test-two-party-ocmgo-sender-route-peer-hosts [] {
    test-log "\n[test-two-party-ocmgo-sender-route-peer-hosts]"
    let lines = (ocmgo-env-lines "sender" "ocmgo" (fixture-actor) "nc1" "nc2")
    [
        (assert-list-contains $lines "OCM_GO_SENDER_ROUTE_PEER_HOSTS=nc2"
            "sender ROUTE_PEER_HOSTS is receiver short host nc2")
    ]
}

# Two-party ocmgo sender: ROUTE_SUFFIXES is .docker.
def test-two-party-ocmgo-sender-route-suffixes [] {
    test-log "\n[test-two-party-ocmgo-sender-route-suffixes]"
    let lines = (ocmgo-env-lines "sender" "ocmgo" (fixture-actor) "nc1" "nc2")
    [
        (assert-list-contains $lines "OCM_GO_SENDER_ROUTE_SUFFIXES=.docker"
            "sender ROUTE_SUFFIXES is .docker")
    ]
}

# Two-party ocmgo receiver: ROUTE_PEER_HOSTS equals sender short host.
def test-two-party-ocmgo-receiver-route-peer-hosts [] {
    test-log "\n[test-two-party-ocmgo-receiver-route-peer-hosts]"
    let lines = (ocmgo-env-lines "receiver" "ocmgo" (fixture-actor) "nc2" "nc1")
    [
        (assert-list-contains $lines "OCM_GO_RECEIVER_ROUTE_PEER_HOSTS=nc1"
            "receiver ROUTE_PEER_HOSTS is sender short host nc1")
    ]
}

# Two-party ocmgo receiver: ROUTE_SUFFIXES is .docker.
def test-two-party-ocmgo-receiver-route-suffixes [] {
    test-log "\n[test-two-party-ocmgo-receiver-route-suffixes]"
    let lines = (ocmgo-env-lines "receiver" "ocmgo" (fixture-actor) "nc2" "nc1")
    [
        (assert-list-contains $lines "OCM_GO_RECEIVER_ROUTE_SUFFIXES=.docker"
            "receiver ROUTE_SUFFIXES is .docker")
    ]
}

# One-party ocmgo: ROUTE_PEER_HOSTS is blank (no peer host passed).
def test-one-party-ocmgo-route-peer-hosts-blank [] {
    test-log "\n[test-one-party-ocmgo-route-peer-hosts-blank]"
    let lines = (ocmgo-env-lines "sender" "ocmgo" (fixture-actor) "nc1")
    [
        (assert-list-contains $lines "OCM_GO_SENDER_ROUTE_PEER_HOSTS="
            "one-party ocmgo sender ROUTE_PEER_HOSTS is blank")
    ]
}

# One-party ocmgo: ROUTE_SUFFIXES is blank (no peer host passed).
def test-one-party-ocmgo-route-suffixes-blank [] {
    test-log "\n[test-one-party-ocmgo-route-suffixes-blank]"
    let lines = (ocmgo-env-lines "sender" "ocmgo" (fixture-actor) "nc1")
    [
        (assert-list-contains $lines "OCM_GO_SENDER_ROUTE_SUFFIXES="
            "one-party ocmgo sender ROUTE_SUFFIXES is blank")
    ]
}

# Non-ocmgo platform: all OCM_GO var slots are blank regardless of peer_host.
def test-non-ocmgo-platform-vars-blank [] {
    test-log "\n[test-non-ocmgo-platform-vars-blank]"
    let lines = (ocmgo-env-lines "sender" "nextcloud" null "nc1" "nc2")
    [
        (assert-list-contains $lines "OCM_GO_SENDER_ROUTE_PEER_HOSTS="
            "non-ocmgo sender ROUTE_PEER_HOSTS is blank")
        (assert-list-contains $lines "OCM_GO_SENDER_ROUTE_SUFFIXES="
            "non-ocmgo sender ROUTE_SUFFIXES is blank")
        (assert-list-contains $lines "OCM_GO_SENDER_HOST="
            "non-ocmgo sender HOST is blank")
        (assert-list-contains $lines "OCM_GO_SENDER_ADMIN_USER="
            "non-ocmgo sender ADMIN_USER is blank")
        (assert-list-contains $lines "OCM_GO_SENDER_ADMIN_PASSWORD="
            "non-ocmgo sender ADMIN_PASSWORD is blank")
    ]
}

# One-party ocmgo receiver: ROUTE_PEER_HOSTS and ROUTE_SUFFIXES are blank.
def test-one-party-ocmgo-receiver-route-vars-blank [] {
    test-log "\n[test-one-party-ocmgo-receiver-route-vars-blank]"
    let lines = (ocmgo-env-lines "receiver" "ocmgo" (fixture-actor) "nc2")
    [
        (assert-list-contains $lines "OCM_GO_RECEIVER_ROUTE_PEER_HOSTS="
            "one-party ocmgo receiver ROUTE_PEER_HOSTS is blank")
        (assert-list-contains $lines "OCM_GO_RECEIVER_ROUTE_SUFFIXES="
            "one-party ocmgo receiver ROUTE_SUFFIXES is blank")
    ]
}

# Two-party ocmgo sender: host and admin envs are still present alongside route vars.
def test-two-party-ocmgo-sender-host-admin-coexist [] {
    test-log "\n[test-two-party-ocmgo-sender-host-admin-coexist]"
    let lines = (ocmgo-env-lines "sender" "ocmgo" (fixture-actor) "nc1" "nc2")
    [
        (assert-list-contains $lines "OCM_GO_SENDER_HOST=nc1"
            "sender HOST still emitted alongside route vars")
        (assert-list-contains $lines "OCM_GO_SENDER_ADMIN_USER=admin"
            "sender ADMIN_USER still emitted alongside route vars")
        (assert-list-contains $lines "OCM_GO_SENDER_ADMIN_PASSWORD=secret"
            "sender ADMIN_PASSWORD still emitted alongside route vars")
        (assert-list-contains $lines "OCM_GO_SENDER_ROUTE_PEER_HOSTS=nc2"
            "sender ROUTE_PEER_HOSTS present when host/admin also present")
    ]
}

def main [] {
    test-log "=== compose/ocmgo-env-lines Tests ==="
    let results = (
        (test-two-party-ocmgo-sender-route-peer-hosts)
        | append (test-two-party-ocmgo-sender-route-suffixes)
        | append (test-two-party-ocmgo-receiver-route-peer-hosts)
        | append (test-two-party-ocmgo-receiver-route-suffixes)
        | append (test-one-party-ocmgo-route-peer-hosts-blank)
        | append (test-one-party-ocmgo-route-suffixes-blank)
        | append (test-one-party-ocmgo-receiver-route-vars-blank)
        | append (test-non-ocmgo-platform-vars-blank)
        | append (test-two-party-ocmgo-sender-host-admin-coexist)
    ) | flatten
    run-suite "compose/ocmgo-env-lines" $SUITE_PATH $results
}
