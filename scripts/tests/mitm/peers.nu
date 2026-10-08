# Run: nu scripts/tests/mitm/peers.nu
const SUITE_PATH = path self
use ../../lib/mitm/peers.nu [endpoint-from-inspect endpoint-is-participant validate-role-endpoints]
use ../../lib/compose/topology-two-party.nu [cookbook-service-names]
use ../../lib/compose/topology-sender-hub.nu [sender-hub-cookbook-service-names]
use ../../lib/domain/core/ocmts-root.nu [get-ocmts-root]
use ../../lib/run/flow-topology.nu [load-flow-topology]
use ../../lib/tests/assert.nu *
use ../../lib/tests/runner.nu [run-suite]

def main [] {
    let proxy = {
        sender: {http: "http://mitm:8080", https: "http://mitm:8080"},
        receiver: {http: "http://mitm:8080", https: "http://mitm:8080"},
    }
    let dynamic = (["10.42.9.6" "10.77.3.6"] | each {|ip|
        let data = {
            Config: {Hostname: "receiver-revad-gateway", Env: ["HTTP_PROXY=http://mitm:8080"]},
            NetworkSettings: {Networks: {
                "run-net": {IPAddress: $ip, Aliases: ["receiver-revad-gateway" null], DNSNames: ["gateway-container"]},
                "other-net": {IPAddress: "192.0.2.9", Aliases: ["wrong"]},
            }},
        }
        let endpoint = (endpoint-from-inspect "run-net" "receiver-revad-gateway" $data)
        [
            (assert-eq $endpoint.ipv4 $ip "current run network IP is used")
            (assert-eq ($endpoint.hosts | first) "receiver-revad-gateway" "gateway primary name remains readable")
            (assert-truthy (not ("wrong" in $endpoint.hosts)) "other-network aliases excluded")
            (assert-eq (endpoint-from-inspect "missing" "receiver-revad-gateway" $data) null "missing network is not fabricated")
        ]
    } | flatten)
    let hub = (endpoint-from-inspect "run-net" "sender-hub" {
        Config: {Hostname: "sender-hub"},
        NetworkSettings: {Networks: {"run-net": {IPAddress: "10.42.9.5", Aliases: ["sender-hub" "jupyterhub1.docker"]}}},
    })
    let duplicates = (try {
        validate-role-endpoints {
            sender: {endpoints: [{service: "sender", ipv4: "10.42.9.2", hosts: ["same"]}]},
            receiver: {endpoints: [{service: "receiver", ipv4: "10.42.9.3", hosts: ["same"]}]},
        }
        "accepted"
    } catch { "rejected" })
    let root = (get-ocmts-root)
    let topology = (load-flow-topology $root)
    let results = ($dynamic | append [
        (assert-eq ($hub.hosts | first) "jupyterhub1.docker" "public hub alias has priority")
        (assert-truthy (endpoint-is-participant "receiver-revad-gateway" [] ["HTTP_PROXY=http://mitm:8080"] $proxy) "proxied gateway included")
        (assert-truthy (endpoint-is-participant "receiver-revad-authprovider" [] ["https_proxy=http://mitm:8080"] $proxy) "lowercase proxy setting included")
        (assert-truthy (endpoint-is-participant "sender-hub" ["sender-hub"] [] $proxy) "declared hub included without proxy")
        (assert-truthy (endpoint-is-participant "sender" [] [] $proxy) "primary included without proxy")
        (assert-truthy (not (endpoint-is-participant "sender-db" [] ["NO_PROXY=sender-db"] $proxy)) "database excluded")
        (assert-truthy (not (endpoint-is-participant "receiver-cache" [] [] $proxy)) "cache excluded")
        (assert-truthy (not (endpoint-is-participant "receiver-idp" [] ["HTTP_PROXY=http://other:8080"] $proxy)) "other proxy excluded")
        (assert-eq $duplicates "rejected" "duplicate host ownership rejected")
        (assert-list-contains (cookbook-service-names $root "cernbox" "receiver") "receiver-revad-gateway" "party enumeration export usable")
        (assert-list-contains (sender-hub-cookbook-service-names $root "nextcloud" "webapp-share" $topology) "sender-hub" "hub enumeration export usable")
    ])
    run-suite "mitm/peers" $SUITE_PATH $results
}
