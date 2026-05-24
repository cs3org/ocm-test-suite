# Unit tests for ocmgo-env-lines and execution-cidr in
# scripts/lib/compose/topology-common.nu.
# Covers the route env contract: two-party ocmgo sender/receiver,
# one-party ocmgo (no peer), non-ocmgo platforms (all slots blank), and
# deterministic CIDR generation from execution_id.
# Run: nu scripts/tests/compose/ocmgo-env-lines.nu

const SUITE_PATH = path self

use ../../lib/compose/topology-common.nu [ocmgo-env-lines execution-cidr]
use ../../lib/tests/assert.nu *
use ../../lib/tests/runner.nu [run-suite]

# Minimal actor fixture for ocmgo tests.
def fixture-actor [] {
    {username: "admin", password: "secret", platform: "ocmgo"}
}

# A representative execution_id used in CIDR derivation tests.
def fixture-exec-id [] { "20260523t194026-c5e486b4" }

# CIDR derived from fixture-exec-id: tail=c5e486b4, b=0xc5=197, c=0xe4=228.
def fixture-exec-cidr [] { "10.197.228.0/24" }

# Two-party ocmgo sender: ROUTE_SUFFIXES is .docker.
def test-two-party-ocmgo-sender-route-suffixes [] {
    test-log "\n[test-two-party-ocmgo-sender-route-suffixes]"
    let lines = (ocmgo-env-lines "sender" "ocmgo" (fixture-actor) "nc1" "nc2.docker" (fixture-exec-cidr))
    [
        (assert-list-contains $lines "OCM_GO_SENDER_ROUTE_SUFFIXES=.docker"
            "sender ROUTE_SUFFIXES is .docker")
    ]
}

# Two-party ocmgo sender: ROUTE_PRIVATE_CIDRS equals the execution CIDR.
def test-two-party-ocmgo-sender-route-private-cidrs [] {
    test-log "\n[test-two-party-ocmgo-sender-route-private-cidrs]"
    let lines = (ocmgo-env-lines "sender" "ocmgo" (fixture-actor) "nc1" "nc2.docker" (fixture-exec-cidr))
    [
        (assert-list-contains $lines
            $"OCM_GO_SENDER_ROUTE_PRIVATE_CIDRS=(fixture-exec-cidr)"
            "sender ROUTE_PRIVATE_CIDRS is the execution CIDR")
    ]
}

# Two-party ocmgo receiver: ROUTE_SUFFIXES is .docker.
def test-two-party-ocmgo-receiver-route-suffixes [] {
    test-log "\n[test-two-party-ocmgo-receiver-route-suffixes]"
    let lines = (ocmgo-env-lines "receiver" "ocmgo" (fixture-actor) "nc2" "nc1.docker" (fixture-exec-cidr))
    [
        (assert-list-contains $lines "OCM_GO_RECEIVER_ROUTE_SUFFIXES=.docker"
            "receiver ROUTE_SUFFIXES is .docker")
    ]
}

# Two-party ocmgo receiver: ROUTE_PRIVATE_CIDRS equals the execution CIDR.
def test-two-party-ocmgo-receiver-route-private-cidrs [] {
    test-log "\n[test-two-party-ocmgo-receiver-route-private-cidrs]"
    let lines = (ocmgo-env-lines "receiver" "ocmgo" (fixture-actor) "nc2" "nc1.docker" (fixture-exec-cidr))
    [
        (assert-list-contains $lines
            $"OCM_GO_RECEIVER_ROUTE_PRIVATE_CIDRS=(fixture-exec-cidr)"
            "receiver ROUTE_PRIVATE_CIDRS is the execution CIDR")
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

# One-party ocmgo: ROUTE_PRIVATE_CIDRS is blank (no peer host means no route).
def test-one-party-ocmgo-route-private-cidrs-blank [] {
    test-log "\n[test-one-party-ocmgo-route-private-cidrs-blank]"
    let lines = (ocmgo-env-lines "sender" "ocmgo" (fixture-actor) "nc1")
    [
        (assert-list-contains $lines "OCM_GO_SENDER_ROUTE_PRIVATE_CIDRS="
            "one-party ocmgo sender ROUTE_PRIVATE_CIDRS is blank")
    ]
}

# Non-ocmgo platform: all OCM_GO var slots are blank regardless of peer_host.
def test-non-ocmgo-platform-vars-blank [] {
    test-log "\n[test-non-ocmgo-platform-vars-blank]"
    let lines = (ocmgo-env-lines "sender" "nextcloud" null "nc1" "nc2")
    [
        (assert-list-contains $lines "OCM_GO_SENDER_ROUTE_SUFFIXES="
            "non-ocmgo sender ROUTE_SUFFIXES is blank")
        (assert-list-contains $lines "OCM_GO_SENDER_ROUTE_PRIVATE_CIDRS="
            "non-ocmgo sender ROUTE_PRIVATE_CIDRS is blank")
        (assert-list-contains $lines "OCM_GO_SENDER_HOST="
            "non-ocmgo sender HOST is blank")
        (assert-list-contains $lines "OCM_GO_SENDER_ADMIN_USER="
            "non-ocmgo sender ADMIN_USER is blank")
        (assert-list-contains $lines "OCM_GO_SENDER_ADMIN_PASSWORD="
            "non-ocmgo sender ADMIN_PASSWORD is blank")
    ]
}

# One-party ocmgo receiver: all route vars are blank.
def test-one-party-ocmgo-receiver-route-vars-blank [] {
    test-log "\n[test-one-party-ocmgo-receiver-route-vars-blank]"
    let lines = (ocmgo-env-lines "receiver" "ocmgo" (fixture-actor) "nc2")
    [
        (assert-list-contains $lines "OCM_GO_RECEIVER_ROUTE_SUFFIXES="
            "one-party ocmgo receiver ROUTE_SUFFIXES is blank")
        (assert-list-contains $lines "OCM_GO_RECEIVER_ROUTE_PRIVATE_CIDRS="
            "one-party ocmgo receiver ROUTE_PRIVATE_CIDRS is blank")
    ]
}

# Two-party ocmgo sender: host and admin envs are still present alongside route vars.
def test-two-party-ocmgo-sender-host-admin-coexist [] {
    test-log "\n[test-two-party-ocmgo-sender-host-admin-coexist]"
    let lines = (ocmgo-env-lines "sender" "ocmgo" (fixture-actor) "nc1" "nc2.docker" (fixture-exec-cidr))
    [
        (assert-list-contains $lines "OCM_GO_SENDER_HOST=nc1"
            "sender HOST still emitted alongside route vars")
        (assert-list-contains $lines "OCM_GO_SENDER_ADMIN_USER=admin"
            "sender ADMIN_USER still emitted alongside route vars")
        (assert-list-contains $lines "OCM_GO_SENDER_ADMIN_PASSWORD=secret"
            "sender ADMIN_PASSWORD still emitted alongside route vars")
        (assert-list-contains $lines
            $"OCM_GO_SENDER_ROUTE_PRIVATE_CIDRS=(fixture-exec-cidr)"
            "sender ROUTE_PRIVATE_CIDRS present alongside host/admin")
    ]
}

# execution-cidr: derives correct /24 from known execution_id tail.
def test-execution-cidr-known-tail [] {
    test-log "\n[test-execution-cidr-known-tail]"
    # tail c5e486b4: 0xc5=197, 0xe4=228 -> 10.197.228.0/24
    let cidr = (execution-cidr (fixture-exec-id))
    [
        (assert-eq $cidr (fixture-exec-cidr)
            "execution-cidr produces 10.197.228.0/24 from tail c5e486b4")
    ]
}

# execution-cidr: two all-zero hex pairs give 10.0.0.0/24.
def test-execution-cidr-zero-tail [] {
    test-log "\n[test-execution-cidr-zero-tail]"
    let cidr = (execution-cidr "20260101t000000-00000000")
    [
        (assert-eq $cidr "10.0.0.0/24"
            "execution-cidr with all-zero tail gives 10.0.0.0/24")
    ]
}

# execution-cidr: different hex pairs produce distinct /24 subnets.
def test-execution-cidr-distinct [] {
    test-log "\n[test-execution-cidr-distinct]"
    # tail 0a0b0000: 0x0a=10, 0x0b=11 -> 10.10.11.0/24
    let cidr_a = (execution-cidr "20260101t000000-0a0b0000")
    # tail ff010000: 0xff=255, 0x01=1 -> 10.255.1.0/24
    let cidr_b = (execution-cidr "20260101t000000-ff010000")
    [
        (assert-eq $cidr_a "10.10.11.0/24"
            "execution-cidr tail 0a0b -> 10.10.11.0/24")
        (assert-eq $cidr_b "10.255.1.0/24"
            "execution-cidr tail ff01 -> 10.255.1.0/24")
        (assert-truthy ($cidr_a != $cidr_b)
            "distinct tails produce distinct CIDRs")
    ]
}

# Two-party ocmgo: null exec_cidr with peer_host set should error.
def test-two-party-ocmgo-null-exec-cidr-fails [] {
    test-log "\n[test-two-party-ocmgo-null-exec-cidr-fails]"
    let err = (try {
        ocmgo-env-lines "sender" "ocmgo" (fixture-actor) "nc1" "nc2.docker" null
        null
    } catch {|e| $e})
    let msg = (try { $err.msg } catch { "" })
    [
        (assert-truthy ($err != null) "null exec_cidr with peer_host should error")
        (assert-string-contains $msg "exec_cidr"
            "null exec_cidr error mentions exec_cidr")
    ]
}

# Two-party ocmgo: empty-string exec_cidr with peer_host set should error.
def test-two-party-ocmgo-empty-exec-cidr-fails [] {
    test-log "\n[test-two-party-ocmgo-empty-exec-cidr-fails]"
    let err = (try {
        ocmgo-env-lines "sender" "ocmgo" (fixture-actor) "nc1" "nc2.docker" ""
        null
    } catch {|e| $e})
    let msg = (try { $err.msg } catch { "" })
    [
        (assert-truthy ($err != null) "empty exec_cidr with peer_host should error")
        (assert-string-contains $msg "exec_cidr"
            "empty exec_cidr error mentions exec_cidr")
    ]
}

# One-party ocmgo: null exec_cidr without peer_host is fine (no route envs emitted).
def test-one-party-ocmgo-null-exec-cidr-ok [] {
    test-log "\n[test-one-party-ocmgo-null-exec-cidr-ok]"
    let err = (try {
        ocmgo-env-lines "sender" "ocmgo" (fixture-actor) "nc1" null null
        null
    } catch {|e| $e})
    [
        (assert-null $err "null exec_cidr without peer_host should not error")
    ]
}

# execution-cidr: execution_id with no dash should error (shape invalid).
def test-execution-cidr-no-dash [] {
    test-log "\n[test-execution-cidr-no-dash]"
    let err = (try {
        execution-cidr "20260523t194026c5e486b4"
        null
    } catch {|e| $e})
    let msg = (try { $err.msg } catch { "" })
    [
        (assert-truthy ($err != null) "execution_id without dash should error")
        (assert-string-contains $msg "shape invalid"
            "no-dash error mentions shape invalid")
    ]
}

# execution-cidr: execution_id with tail shorter than 8 chars should error.
def test-execution-cidr-short-tail [] {
    test-log "\n[test-execution-cidr-short-tail]"
    let err = (try {
        execution-cidr "20260523t194026-abc"
        null
    } catch {|e| $e})
    let msg = (try { $err.msg } catch { "" })
    [
        (assert-truthy ($err != null) "execution_id with short tail should error")
        (assert-string-contains $msg "shape invalid"
            "short-tail error mentions shape invalid")
    ]
}

# execution-cidr: execution_id with non-hexadecimal tail should error.
def test-execution-cidr-nonhex-tail [] {
    test-log "\n[test-execution-cidr-nonhex-tail]"
    let err = (try {
        execution-cidr "20260523t194026-zzzzzzzz"
        null
    } catch {|e| $e})
    let msg = (try { $err.msg } catch { "" })
    [
        (assert-truthy ($err != null) "execution_id with non-hex tail should error")
        (assert-string-contains $msg "shape invalid"
            "nonhex-tail error mentions shape invalid")
    ]
}

# execution-cidr: uppercase hex tail must be rejected (contract is lowercase only).
def test-execution-cidr-uppercase-tail-fails [] {
    test-log "\n[test-execution-cidr-uppercase-tail-fails]"
    let err = (try {
        execution-cidr "20260523t194026-C5E486B4"
        null
    } catch {|e| $e})
    let msg = (try { $err.msg } catch { "" })
    [
        (assert-truthy ($err != null) "uppercase hex tail should error")
        (assert-string-contains $msg "shape invalid"
            "uppercase-tail error mentions shape invalid")
    ]
}

# execution-cidr: tail longer than 8 chars must be rejected (exact length required).
def test-execution-cidr-long-tail-fails [] {
    test-log "\n[test-execution-cidr-long-tail-fails]"
    let err = (try {
        execution-cidr "20260523t194026-c5e486b4aa"
        null
    } catch {|e| $e})
    let msg = (try { $err.msg } catch { "" })
    [
        (assert-truthy ($err != null) "tail longer than 8 chars should error")
        (assert-string-contains $msg "shape invalid"
            "long-tail error mentions shape invalid")
    ]
}

# execution-cidr: CIDR depends only on chars 16-23 (the tail); timestamp is irrelevant.
def test-execution-cidr-tail-offset-determines-cidr [] {
    test-log "\n[test-execution-cidr-tail-offset-determines-cidr]"
    # Same 8-char tail c5e486b4 with two different valid timestamps must
    # produce the same CIDR, confirming extraction uses the fixed offset 16..23.
    let cidr_a = (execution-cidr "20260101t000000-c5e486b4")
    let cidr_b = (execution-cidr "20260523t194026-c5e486b4")
    [
        (assert-eq $cidr_a (fixture-exec-cidr)
            "same tail with any valid timestamp yields 10.197.228.0/24")
        (assert-eq $cidr_a $cidr_b
            "timestamp prefix does not affect CIDR; only tail chars 16-23 matter")
    ]
}

def main [] {
    test-log "=== compose/ocmgo-env-lines Tests ==="
    let results = (
        (test-two-party-ocmgo-sender-route-suffixes)
        | append (test-two-party-ocmgo-sender-route-private-cidrs)
        | append (test-two-party-ocmgo-receiver-route-suffixes)
        | append (test-two-party-ocmgo-receiver-route-private-cidrs)
        | append (test-one-party-ocmgo-route-suffixes-blank)
        | append (test-one-party-ocmgo-route-private-cidrs-blank)
        | append (test-one-party-ocmgo-receiver-route-vars-blank)
        | append (test-non-ocmgo-platform-vars-blank)
        | append (test-two-party-ocmgo-sender-host-admin-coexist)
        | append (test-execution-cidr-known-tail)
        | append (test-execution-cidr-zero-tail)
        | append (test-execution-cidr-distinct)
        | append (test-two-party-ocmgo-null-exec-cidr-fails)
        | append (test-two-party-ocmgo-empty-exec-cidr-fails)
        | append (test-one-party-ocmgo-null-exec-cidr-ok)
        | append (test-execution-cidr-no-dash)
        | append (test-execution-cidr-short-tail)
        | append (test-execution-cidr-nonhex-tail)
        | append (test-execution-cidr-uppercase-tail-fails)
        | append (test-execution-cidr-long-tail-fails)
        | append (test-execution-cidr-tail-offset-determines-cidr)
    ) | flatten
    run-suite "compose/ocmgo-env-lines" $SUITE_PATH $results
}
