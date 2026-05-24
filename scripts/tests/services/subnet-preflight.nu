# Tests for scripts/lib/services/subnet-preflight.nu.
# Covers cidr-overlaps (pure), find-conflict-networks (pure), and the
# check-subnet-preflight entry point using injected network fixtures.
# Run: nu scripts/tests/services/subnet-preflight.nu

const SUITE_PATH = path self

use ../../lib/services/subnet-preflight.nu [
    cidr-overlaps
    find-conflict-networks
    check-subnet-preflight
]
use ../../lib/tests/assert.nu *
use ../../lib/tests/runner.nu [run-suite]

# --- cidr-overlaps tests ---

def test-cidr-overlaps-identical [] {
    test-log "\n[test-cidr-overlaps-identical]"
    [
        (assert-truthy (cidr-overlaps "10.42.0.0/24" "10.42.0.0/24")
            "identical CIDRs overlap")
    ]
}

def test-cidr-overlaps-contained [] {
    test-log "\n[test-cidr-overlaps-contained]"
    [
        (assert-truthy (cidr-overlaps "10.42.0.0/24" "10.42.0.0/16")
            "/24 is contained in wider /16")
        (assert-truthy (cidr-overlaps "10.42.0.0/16" "10.42.0.0/24")
            "/16 contains the /24 (symmetric)")
        (assert-truthy (cidr-overlaps "10.42.5.0/24" "10.42.0.0/16")
            "/24 inside /16 different third octet")
    ]
}

def test-cidr-overlaps-distinct [] {
    test-log "\n[test-cidr-overlaps-distinct]"
    [
        (assert-truthy (not (cidr-overlaps "10.42.0.0/24" "10.43.0.0/24"))
            "adjacent /24s do not overlap")
        (assert-truthy (not (cidr-overlaps "10.42.0.0/24" "172.16.0.0/12"))
            "different RFC-1918 ranges do not overlap")
        (assert-truthy (not (cidr-overlaps "192.168.1.0/24" "192.168.2.0/24"))
            "192.168.1 vs 192.168.2 do not overlap")
    ]
}

def test-cidr-overlaps-edge-prefix-lengths [] {
    test-log "\n[test-cidr-overlaps-edge-prefix-lengths]"
    [
        (assert-truthy (cidr-overlaps "10.0.0.0/8" "10.42.0.0/24")
            "/8 contains a /24 in same block")
        (assert-truthy (not (cidr-overlaps "10.0.0.0/8" "172.16.0.0/24"))
            "/8 does not overlap different class-A block")
    ]
}

# prefix-to-mask boundary: /0 is the default route covering all addresses.
def test-cidr-overlaps-prefix-zero-covers-all [] {
    test-log "\n[test-cidr-overlaps-prefix-zero-covers-all]"
    [
        (assert-truthy (cidr-overlaps "0.0.0.0/0" "10.42.5.0/24")
            "/0 default route overlaps any /24")
        (assert-truthy (cidr-overlaps "10.42.5.0/24" "0.0.0.0/0")
            "/24 is contained in the /0 default route (symmetric)")
        (assert-truthy (cidr-overlaps "0.0.0.0/0" "192.168.0.0/16")
            "/0 default route overlaps any RFC-1918 /16")
    ]
}

# prefix-to-mask boundary: /32 is a single host address.
def test-cidr-overlaps-prefix-32-host [] {
    test-log "\n[test-cidr-overlaps-prefix-32-host]"
    [
        (assert-truthy (cidr-overlaps "10.42.5.1/32" "10.42.5.0/24")
            "/32 host is contained in its /24")
        (assert-truthy (cidr-overlaps "10.42.5.0/24" "10.42.5.1/32")
            "/24 contains a /32 host (symmetric)")
        (assert-truthy (not (cidr-overlaps "10.42.5.1/32" "10.42.6.0/24"))
            "/32 host does not overlap a different /24")
        (assert-truthy (cidr-overlaps "10.42.5.1/32" "10.42.5.1/32")
            "identical /32 host addresses overlap")
    ]
}

def test-cidr-overlaps-malformed-returns-false [] {
    test-log "\n[test-cidr-overlaps-malformed-returns-false]"
    [
        (assert-truthy (not (cidr-overlaps "not-a-cidr" "10.42.0.0/24"))
            "malformed first arg returns false")
        (assert-truthy (not (cidr-overlaps "10.42.0.0/24" "not-a-cidr"))
            "malformed second arg returns false")
        (assert-truthy (not (cidr-overlaps "fd00::/64" "10.42.0.0/24"))
            "IPv6 CIDR returns false")
        (assert-truthy (not (cidr-overlaps "10.42.0.0/24" "10.42.bad.0/24"))
            "malformed IPv4 octet with slash returns false")
        (assert-truthy (not (cidr-overlaps "10.42.0.0/not-a-prefix" "10.42.0.0/24"))
            "malformed prefix with slash returns false")
        (assert-truthy (not (cidr-overlaps "" "10.42.0.0/24"))
            "empty string returns false")
    ]
}

def test-cidr-overlaps-short-ip-returns-false [] {
    test-log "\n[test-cidr-overlaps-short-ip-returns-false]"
    [
        (assert-truthy (not (cidr-overlaps "10.1.1/24" "10.42.0.0/24"))
            "3-octet IP first arg returns false")
        (assert-truthy (not (cidr-overlaps "10.42.0.0/24" "10.1.1/24"))
            "3-octet IP second arg returns false")
        (assert-truthy (not (cidr-overlaps "192.168.1/16" "192.168.0.0/16"))
            "3-octet IP does not spuriously match a valid CIDR")
    ]
}

def test-cidr-overlaps-out-of-range-inputs [] {
    test-log "\n[test-cidr-overlaps-out-of-range-inputs]"
    [
        (assert-truthy (not (cidr-overlaps "256.1.1.0/24" "10.0.0.0/8"))
            "octet 256 out of range returns false")
        (assert-truthy (not (cidr-overlaps "10.0.300.0/24" "10.0.0.0/8"))
            "octet 300 out of range returns false")
        (assert-truthy (not (cidr-overlaps "10.0.0.0/33" "10.0.0.0/24"))
            "prefix /33 out of range returns false")
        (assert-truthy (not (cidr-overlaps "10.0.0.0/24" "10.0.0.0/33"))
            "prefix /33 in second arg returns false")
    ]
}

# --- find-conflict-networks tests ---

def test-find-conflicts-no-networks [] {
    test-log "\n[test-find-conflicts-no-networks]"
    let result = (find-conflict-networks "10.42.5.0/24" [])
    [
        (assert-eq ($result | length) 0 "empty network list yields no conflicts")
    ]
}

def test-find-conflicts-no-overlap [] {
    test-log "\n[test-find-conflicts-no-overlap]"
    let nets = [
        {name: "bridge", subnets: ["172.17.0.0/16"]}
        {name: "host", subnets: []}
        {name: "some-other", subnets: ["10.43.0.0/24"]}
    ]
    let result = (find-conflict-networks "10.42.5.0/24" $nets)
    [
        (assert-eq ($result | length) 0 "non-overlapping networks yield no conflicts")
    ]
}

def test-find-conflicts-one-overlap [] {
    test-log "\n[test-find-conflicts-one-overlap]"
    let nets = [
        {name: "bridge", subnets: ["172.17.0.0/16"]}
        {name: "ocmts--cell-foo--20260101t120000-c5e486b4", subnets: ["10.197.228.0/24"]}
        {name: "some-wide", subnets: ["10.0.0.0/8"]}
    ]
    # 10.197.228.0/24 exactly matches exec_cidr; "some-wide" /8 also contains it
    let result = (find-conflict-networks "10.197.228.0/24" $nets)
    [
        (assert-eq ($result | length) 2 "two overlapping networks found")
        (assert-eq ($result | get 0 | get name)
            "ocmts--cell-foo--20260101t120000-c5e486b4"
            "first conflict is the exact-match network")
        (assert-eq ($result | get 1 | get name)
            "some-wide"
            "second conflict is the wider /8 network")
    ]
}

def test-find-conflicts-subnet-list-per-network [] {
    test-log "\n[test-find-conflicts-subnet-list-per-network]"
    let nets = [
        {name: "multi-subnet-net", subnets: ["192.168.50.0/24" "10.42.5.0/24" "172.20.0.0/16"]}
    ]
    let result = (find-conflict-networks "10.42.5.0/24" $nets)
    [
        (assert-eq ($result | length) 1 "conflict detected in multi-subnet network")
        (assert-eq ($result | get 0 | get name) "multi-subnet-net" "correct network name")
        (assert-eq ($result | get 0 | get conflicting_subnets) ["10.42.5.0/24"]
            "only the overlapping subnet is reported")
    ]
}

def test-find-conflicts-empty-subnets-skipped [] {
    test-log "\n[test-find-conflicts-empty-subnets-skipped]"
    let nets = [
        {name: "host", subnets: []}
        {name: "none", subnets: []}
    ]
    let result = (find-conflict-networks "10.42.5.0/24" $nets)
    [
        (assert-eq ($result | length) 0 "networks with empty subnets are not flagged")
    ]
}

def test-find-conflicts-missing-subnets-field [] {
    test-log "\n[test-find-conflicts-missing-subnets-field]"
    # Records without a subnets key (e.g. injected fixtures or future callers) must
    # not raise an error and must not produce false-positive conflicts.
    let nets = [
        {name: "no-subnets-key"}
        {name: "has-match", subnets: ["10.42.5.0/24"]}
    ]
    let result = (find-conflict-networks "10.42.5.0/24" $nets)
    [
        (assert-eq ($result | length) 1
            "record missing subnets field is not flagged as conflict")
        (assert-eq ($result | get 0 | get name) "has-match"
            "only the network with a matching subnet is reported")
    ]
}

# --- check-subnet-preflight tests ---

def test-preflight-passes-no-networks [] {
    test-log "\n[test-preflight-passes-no-networks]"
    let result = (try {
        check-subnet-preflight "10.42.5.0/24" --networks []
        "ok"
    } catch {|e| $"error: ($e.msg)"})
    [
        (assert-eq $result "ok" "preflight passes when no active networks")
    ]
}

def test-preflight-passes-no-overlap [] {
    test-log "\n[test-preflight-passes-no-overlap]"
    let nets = [
        {name: "bridge", subnets: ["172.17.0.0/16"]}
        {name: "ipv6-only", subnets: ["fd00::/64"]}
        {name: "other", subnets: ["10.99.0.0/24"]}
        {name: "malformed", subnets: ["10.42.bad.0/24"]}
    ]
    let result = (try {
        check-subnet-preflight "10.42.5.0/24" --networks $nets
        "ok"
    } catch {|e| $"error: ($e.msg)"})
    [
        (assert-eq $result "ok" "preflight passes when no overlap")
    ]
}

def test-preflight-fails-on-overlap [] {
    test-log "\n[test-preflight-fails-on-overlap]"
    let nets = [
        {name: "bridge", subnets: ["172.17.0.0/16"]}
        {name: "stale-run-net", subnets: ["10.42.5.0/24"]}
    ]
    let result = (try {
        check-subnet-preflight "10.42.5.0/24" --networks $nets
        "ok"
    } catch {|e| $e.msg})
    [
        (assert-truthy ($result | str contains "10.42.5.0/24")
            "error message includes exec_cidr")
        (assert-truthy ($result | str contains "stale-run-net")
            "error message includes conflicting network name")
        (assert-truthy ($result | str contains "10.42.5.0/24")
            "error message includes conflicting subnet")
    ]
}

def test-preflight-error-names-multiple-conflicts [] {
    test-log "\n[test-preflight-error-names-multiple-conflicts]"
    let nets = [
        {name: "net-alpha", subnets: ["10.42.5.0/24"]}
        {name: "net-beta", subnets: ["10.42.0.0/16"]}
    ]
    let result = (try {
        check-subnet-preflight "10.42.5.0/24" --networks $nets
        "ok"
    } catch {|e| $e.msg})
    [
        (assert-truthy ($result | str contains "net-alpha")
            "error message includes first conflicting network")
        (assert-truthy ($result | str contains "net-beta")
            "error message includes second conflicting network")
    ]
}

# Prove that a missing docker binary is not silently swallowed.
# with-env { PATH: "" } guarantees ^docker cannot be resolved, so the
# default loader path (no --networks) must raise an error whose message
# makes it clear the check could not proceed.
def test-preflight-docker-not-found-is-error [] {
    test-log "\n[test-preflight-docker-not-found-is-error]"
    let result = (try {
        with-env { PATH: "" } {
            check-subnet-preflight "10.42.5.0/24"
        }
        "ok"
    } catch {|e| $e.msg})
    [
        (assert-truthy ($result | str contains "docker binary not found")
            "missing docker binary must surface a clear error, not silently pass")
    ]
}

def test-preflight-passes-when-exec-cidr-from-known-id [] {
    test-log "\n[test-preflight-passes-when-exec-cidr-from-known-id]"
    # execution-id 20260101t120000-c5e486b4 -> 10.197.228.0/24
    # Provide only non-overlapping nets
    let nets = [
        {name: "bridge", subnets: ["172.17.0.0/16"]}
        {name: "host", subnets: []}
    ]
    let result = (try {
        check-subnet-preflight "10.197.228.0/24" --networks $nets
        "ok"
    } catch {|e| $"error: ($e.msg)"})
    [
        (assert-eq $result "ok"
            "preflight passes for execution-cidr 10.197.228.0/24 with no conflict")
    ]
}

def main [] {
    test-log "=== services/subnet-preflight tests ==="
    let results = (
        (test-cidr-overlaps-identical)
        | append (test-cidr-overlaps-contained)
        | append (test-cidr-overlaps-distinct)
        | append (test-cidr-overlaps-edge-prefix-lengths)
        | append (test-cidr-overlaps-prefix-zero-covers-all)
        | append (test-cidr-overlaps-prefix-32-host)
        | append (test-cidr-overlaps-malformed-returns-false)
        | append (test-cidr-overlaps-short-ip-returns-false)
        | append (test-cidr-overlaps-out-of-range-inputs)
        | append (test-find-conflicts-no-networks)
        | append (test-find-conflicts-no-overlap)
        | append (test-find-conflicts-one-overlap)
        | append (test-find-conflicts-subnet-list-per-network)
        | append (test-find-conflicts-empty-subnets-skipped)
        | append (test-find-conflicts-missing-subnets-field)
        | append (test-preflight-passes-no-networks)
        | append (test-preflight-passes-no-overlap)
        | append (test-preflight-fails-on-overlap)
        | append (test-preflight-error-names-multiple-conflicts)
        | append (test-preflight-docker-not-found-is-error)
        | append (test-preflight-passes-when-exec-cidr-from-known-id)
    ) | flatten
    run-suite "services/subnet-preflight" $SUITE_PATH $results
}
