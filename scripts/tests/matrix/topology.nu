# Flow Topology SSOT Tests.
# Run: nu scripts/tests/matrix/topology.nu
# Returns exit 0 on all pass, exit 1 with details on failure.

const SUITE_PATH = path self

use ../../lib/tests/assert.nu *
use ../../lib/tests/runner.nu [run-suite]
use ../../lib/matrix/topology.nu [flow-is-two-party assert-topology-matches]
use ../../lib/matrix/cell.nu [compute-cell]
use ../../lib/matrix/rules-gen.nu [load-matrix-rules]
use ../../lib/matrix/cells.nu [expand-matrix-cells]
use ../../lib/compose/render.nu [write-compose-overlays]
use ../../lib/compose/topology-common.nu [execution-cidr]
use ../../lib/compose/topology-sender-hub.nu [
    SENDER_HUB_JUPYTER_ENV_LINE
    SENDER_HUB_OAUTH_ENV_LINE
    SENDER_HUB_OAUTH_VOLUME_LINE
]
use ../../lib/images/resolve.nu [resolve-images resolve-receiver-images]
use ../../lib/run/flow-topology.nu [flow-has-sender-hub load-flow-topology]
use ../../lib/run/execution-id.nu [execution-temp-path]

def test-login-is-one-party [] {
    test-log "\n[test-login-is-one-party]"
    let result = (flow-is-two-party "login")
    [
        (assert-eq $result false "login flow has two_party=false")
    ]
}

def test-share-with-is-two-party [] {
    test-log "\n[test-share-with-is-two-party]"
    let result = (flow-is-two-party "share-with")
    [
        (assert-eq $result true "share-with flow has two_party=true")
    ]
}

def test-assert-topology-matches-ok [] {
    test-log "\n[test-assert-topology-matches-ok]"
    let errored = try {
        assert-topology-matches "login" false "test"
        false
    } catch {
        true
    }
    [
        (assert-eq $errored false "assert-topology-matches passes when derived matches canonical")
    ]
}

def test-assert-topology-mismatch-errors [] {
    test-log "\n[test-assert-topology-mismatch-errors]"
    let got_mismatch_msg = try {
        assert-topology-matches "login" true "test"
        false
    } catch {|e|
        ($e.msg | str contains "Topology mismatch")
    }
    [
        (assert-truthy $got_mismatch_msg "assert-topology-matches errors with 'Topology mismatch' on wrong derived value")
    ]
}

def test-compute-cell-login-one-party-ok [] {
    test-log "\n[test-compute-cell-login-one-party-ok]"
    let cell = (compute-cell "login" "nextcloud" "v33" "chrome")
    [
        (assert-eq $cell.is_two_party false "login one-party cell has is_two_party=false")
        (assert-eq $cell.matrix_key "login__nextcloud"
            "login one-party cell has matrix_key login__nextcloud")
        (assert-eq $cell.cell_id "login__nextcloud-v33"
            "login one-party cell_id shape")
        (assert-eq $cell.artifact_name "cell-login-nextcloud-v33"
            "login one-party artifact_name shape")
    ]
}

def test-compute-cell-login-with-receiver-errors [] {
    test-log "\n[test-compute-cell-login-with-receiver-errors]"
    let got_msg = try {
        compute-cell "login" "nextcloud" "v33" "chrome" "nextcloud" "v33"
        ""
    } catch {|e|
        $e.msg
    }
    [
        (assert-string-contains $got_msg "one-party"
            "compute-cell errors when receiver given to one-party flow")
        (assert-string-contains $got_msg "--receiver-platform"
            "compute-cell spurious receiver error names --receiver-platform")
    ]
}

def test-compute-cell-share-with-two-party-ok [] {
    test-log "\n[test-compute-cell-share-with-two-party-ok]"
    let cell = (compute-cell "share-with" "nextcloud" "v33" "chrome" "nextcloud" "v33")
    [
        (assert-eq $cell.is_two_party true "share-with two-party cell has is_two_party=true")
        (assert-eq $cell.matrix_key "share-with__nextcloud__nextcloud"
            "share-with two-party matrix_key shape")
        (assert-eq $cell.cell_id "share-with__nextcloud-v33__nextcloud-v33"
            "share-with two-party cell_id shape")
        (assert-eq $cell.artifact_name "cell-share-with-nextcloud-v33-nextcloud-v33"
            "share-with two-party artifact_name shape")
    ]
}

def test-compute-cell-share-with-no-receiver-errors [] {
    test-log "\n[test-compute-cell-share-with-no-receiver-errors]"
    let got_msg = try {
        compute-cell "share-with" "nextcloud" "v33" "chrome"
        ""
    } catch {|e|
        $e.msg
    }
    [
        (assert-string-contains $got_msg "requires --receiver-platform"
            "compute-cell errors when no receiver given for two-party flow")
    ]
}

const REVAD_MODES = [
    "gateway"
    "dataprovider-localhome"
    "dataprovider-ocm"
    "dataprovider-sciencemesh"
    "authprovider-oidc"
    "authprovider-machine"
    "authprovider-ocmshares"
    "authprovider-ocmsharecode"
    "authprovider-ocmexchangedtoken"
    "authprovider-publicshares"
    "shareproviders"
    "groupuserproviders"
]

const CERNBOX_CELL_IDS = [
    "contact-token__cernbox-v11__cernbox-v11"
    "contact-token__cernbox-v11__nextcloud-v35"
    "contact-token__cernbox-v11__ocis-v8"
    "contact-token__cernbox-v11__opencloud-v6"
    "contact-token__nextcloud-v35__cernbox-v11"
    "contact-token__ocis-v8__cernbox-v11"
    "contact-token__opencloud-v6__cernbox-v11"
    "login__cernbox-v11"
    "webapp-share__nextcloud-v35__cernbox-v11"
]

const REGISTRY_COMMAND = ["nats-server" "-js" "-sd" "/data" "-m" "8222"]
const REGISTRY_TMPFS = ["/data:size=268435456"]
const REGISTRY_HEALTH_TEST = [
    "CMD-SHELL"
    "wget -qO- 'http://127.0.0.1:8222/healthz?js-enabled-only=true' >/dev/null"
]

def repo-root [] {
    $SUITE_PATH | path dirname | path dirname | path dirname | path dirname | path expand
}

def cernbox-image-mask [] {
    [
        OCMTS_CERNBOX_REGISTRY_IMAGE
        OCMTS_CERNBOX_REVAD_IMAGE
        OCMTS_CERNBOX_REVAD_WEBAPP_SHARE_IMAGE
        OCMTS_CERNBOX_IDP_IMAGE
        OCMTS_CERNBOX_WEB_V11_IMAGE
        OCMTS_CERNBOX_WEB_V11_WEBAPP_SHARE_IMAGE
    ]
    | reduce --fold {} {|k, acc|
        if $k in $env { $acc | upsert $k null } else { $acc }
    }
}

def fresh-exec-id [] {
    let hex = (random uuid | split row "-" | first)
    $"20260102t010203-($hex)"
}

def drop-run [exec_id: string, artifacts: string] {
    try { rm -rf $artifacts } catch { }
    try { rm -rf (execution-temp-path $exec_id) } catch { }
}

def enabled-cells [] {
    let rules = (load-matrix-rules (repo-root))
    let rows = (expand-matrix-cells $rules | where {|row| $row.enabled})
    $rows | group-by cell_id --to-table | each {|group| $group.items | first}
}

def cernbox-roles [cell: record] {
    mut roles = []
    if $cell.sender_platform == "cernbox" {
        $roles = ($roles | append "sender")
    }
    if $cell.is_two_party and ($cell.receiver_platform == "cernbox") {
        $roles = ($roles | append "receiver")
    }
    $roles
}

def strip-hub-lines [text: string] {
    $text
    | str replace --all ("\n" + $SENDER_HUB_JUPYTER_ENV_LINE) ""
    | str replace --all ("\n" + $SENDER_HUB_OAUTH_ENV_LINE) ""
    | str replace --all ("\n" + $SENDER_HUB_OAUTH_VOLUME_LINE) ""
}

def service-deps [spec: record] {
    let raw = ($spec.depends_on? | default null)
    if $raw == null {
        return []
    }
    let kind = ($raw | describe)
    if ($kind | str starts-with "record") {
        $raw | columns
    } else if (($kind | str starts-with "list") or ($kind | str starts-with "table")) {
        $raw | each {|item|
            let item_kind = ($item | describe)
            if ($item_kind | str starts-with "record") {
                $item | columns | first
            } else {
                $item | into string
            }
        }
    } else {
        []
    }
}

def deps-cycle [services: record, name: string, stack: list<string>] {
    if $name in $stack {
        return true
    }
    let spec = ($services | get --optional $name)
    if $spec == null {
        return false
    }
    let deps = (service-deps $spec)
    if ($deps | is-empty) {
        return false
    }
    let next = ($stack | append $name)
    $deps | any {|dep| deps-cycle $services $dep $next}
}

def env-map [path: string] {
    open --raw $path
    | lines
    | where {|line| not ($line | is-empty)}
    | reduce --fold {} {|line, acc|
        let parts = ($line | split row "=")
        let key = ($parts | first)
        let value = ($parts | skip 1 | str join "=")
        $acc | upsert $key $value
    }
}

def brace-names [text: string] {
    let hits = ($text | parse --regex '\$\{(?P<name>[A-Za-z_][A-Za-z0-9_]*)\}')
    if ($hits | is-empty) {
        []
    } else {
        $hits | get name | uniq
    }
}

def ocm-control-lines [prefix: string] {
    [
        ("OCM_ALLOWED_FEDERATION_CIDRS=${" + $prefix + "_REVAD_ALLOWED_FEDERATION_CIDRS}")
        ("OCM_TIMEOUT=${" + $prefix + "_REVAD_OCM_TIMEOUT}")
        ("OCM_CLIENT_INSECURE=${" + $prefix + "_REVAD_OCM_CLIENT_INSECURE}")
        ("OCM_USE_ENV_PROXY=${" + $prefix + "_REVAD_OCM_USE_ENV_PROXY}")
        ("OCM_ALLOW_LOOPBACK_FEDERATION=${" + $prefix + "_REVAD_ALLOW_LOOPBACK_FEDERATION}")
    ]
}

def party-platform [cell: record, role: string] {
    if $role == "sender" { $cell.sender_platform } else { $cell.receiver_platform }
}

def registry-ref [cell: record, role: string] {
    if $role == "sender" {
        (resolve-images $cell.sender_platform $cell.sender_version
            --matrix-key $cell.matrix_key --flow-id $cell.flow_id).bundle.registry
    } else {
        (resolve-receiver-images $cell.receiver_platform $cell.receiver_version
            --matrix-key $cell.matrix_key --flow-id $cell.flow_id).bundle.registry
    }
}

def render-cell [cell: record, exec_id: string, root: string] {
    let artifacts = ($nu.temp-dir | path join $"ocmts-topo-($exec_id)")
    mkdir $artifacts
    let overlay = (write-compose-overlays
        $cell.flow_id
        $cell.sender_platform
        $cell.artifact_name
        $exec_id
        "sender-image:test"
        "cypress:test"
        "cypress-dev:test"
        "mariadb:test"
        "valkey:test"
        $"cypress/e2e/($cell.flow_id)/index.cy.ts"
        $cell.browser
        false
        $root
        $artifacts
        $cell.receiver_platform
        "receiver-image:test"
        "mitm:test"
        $cell.sender_version
        $cell.receiver_version
        {}
        {}
        --cell-id $cell.cell_id)
    {overlay: $overlay, artifacts: $artifacts, exec_id: $exec_id}
}

def check-copied-cookbook [
    cell: record,
    role: string,
    overlay: record,
    root: string,
    topology: record,
] {
    mut problems = []
    let platform = (party-platform $cell $role)
    let copied_path = ($overlay.compose_d | path join $"($role).yml")
    let source_path = ($root | path join "config/compose/cookbooks" $"($platform).($role).yml")
    if not ($copied_path | path exists) {
        return [$"($cell.cell_id) missing ($role).yml"]
    }
    let copied = (open --raw $copied_path)
    let source = (open --raw $source_path)
    let comparable = if ($role == "sender") and (flow-has-sender-hub $cell.flow_id $topology) {
        strip-hub-lines $copied
    } else {
        $copied
    }
    if $comparable != $source {
        $problems = ($problems | append $"($cell.cell_id) ($role).yml bytes differ from the cookbook")
    }
    $problems
}

def check-cernbox-party [
    cell: record,
    role: string,
    overlay: record,
    stack_env: record,
] {
    mut problems = []
    let path = ($overlay.compose_d | path join $"($role).yml")
    let raw = (open --raw $path)
    let services = (open $path).services
    let names = ($services | columns)
    let prefix = ($role | str uppercase)
    let registry = $"($role)-revad-registry"
    let gateway = $"($role)-revad-gateway"
    let idp = $"($role)-idp"
    let revads = ($REVAD_MODES | each {|mode| $"($role)-revad-($mode)"})
    if ($names | length) != 15 {
        $problems = ($problems | append $"($cell.cell_id) ($role) service count ($names | length)")
    }
    let revad_got = ($names | where {|name| ($name | str starts-with $"($role)-revad-") and $name != $registry} | sort)
    if $revad_got != ($revads | sort) {
        $problems = ($problems | append $"($cell.cell_id) ($role) revad set mismatch")
    }
    if not ($registry in $names) {
        $problems = ($problems | append $"($cell.cell_id) ($role) missing registry service")
        return $problems
    }
    let reg = ($services | get $registry)
    if $reg.image != ("${" + $prefix + "_REGISTRY_IMAGE}") {
        $problems = ($problems | append $"($cell.cell_id) ($role) registry image var")
    }
    if $reg.hostname != $registry {
        $problems = ($problems | append $"($cell.cell_id) ($role) registry hostname")
    }
    if $reg.command != $REGISTRY_COMMAND {
        $problems = ($problems | append $"($cell.cell_id) ($role) registry command")
    }
    if $reg.tmpfs != $REGISTRY_TMPFS {
        $problems = ($problems | append $"($cell.cell_id) ($role) registry tmpfs")
    }
    if $reg.restart != "no" {
        $problems = ($problems | append $"($cell.cell_id) ($role) registry restart")
    }
    if $reg.healthcheck.test != $REGISTRY_HEALTH_TEST {
        $problems = ($problems | append $"($cell.cell_id) ($role) registry healthcheck test")
    }
    if $reg.healthcheck.interval != "2s" or $reg.healthcheck.timeout != "2s" or $reg.healthcheck.retries != 30 or $reg.healthcheck.start_period != "5s" {
        $problems = ($problems | append $"($cell.cell_id) ($role) registry healthcheck timing")
    }
    if $reg.networks != ["ocm-net"] {
        $problems = ($problems | append $"($cell.cell_id) ($role) registry networks")
    }
    if not ((service-deps $reg) | is-empty) {
        $problems = ($problems | append $"($cell.cell_id) ($role) registry has dependencies")
    }
    if ("ports" in ($reg | columns)) or ("volumes" in ($reg | columns)) {
        $problems = ($problems | append $"($cell.cell_id) ($role) registry publishes ports or named volumes")
    }
    for name in ($revads | append $registry) {
        let host = ($services | get $name | get hostname)
        if $host != $name {
            $problems = ($problems | append $"($cell.cell_id) ($name) hostname ($host)")
        }
    }
    let root_deps = (service-deps ($services | get $role))
    if not ($registry in $root_deps) {
        $problems = ($problems | append $"($cell.cell_id) ($role) web does not depend on registry")
    }
    for name in $revads {
        let deps = (service-deps ($services | get $name))
        if not ($registry in $deps) {
            $problems = ($problems | append $"($cell.cell_id) ($name) does not depend on registry")
        }
        if $name == $gateway {
            if not ($idp in $deps) {
                $problems = ($problems | append $"($cell.cell_id) gateway dropped idp")
            }
        } else if not ($gateway in $deps) {
            $problems = ($problems | append $"($cell.cell_id) ($name) dropped gateway")
        }
    }
    if ($names | any {|name| deps-cycle $services $name []}) {
        $problems = ($problems | append $"($cell.cell_id) ($role) dependency cycle")
    }
    let other = if $role == "sender" { "receiver" } else { "sender" }
    if ($raw | str contains $"($other)-") or ($raw | str contains (($other | str uppercase) + "_")) {
        $problems = ($problems | append $"($cell.cell_id) ($role) cookbook leaks ($other) names")
    }
    if ($raw | str contains "OCM_TIMEOUT=10") {
        $problems = ($problems | append $"($cell.cell_id) ($role) still has literal OCM_TIMEOUT=10")
    }
    let wanted = (ocm-control-lines $prefix)
    for svc in [$gateway $"($role)-revad-dataprovider-sciencemesh"] {
        let lines = ($services | get $svc | get environment)
        for line in $wanted {
            if not ($line in $lines) {
                $problems = ($problems | append $"($cell.cell_id) ($svc) missing ($line)")
            }
        }
    }
    for name in ($revads | where {|item| $item != $gateway and $item != $"($role)-revad-dataprovider-sciencemesh"}) {
        let lines = ($services | get $name | get environment)
        if ($lines | any {|line| $line | str starts-with "OCM_TIMEOUT"}) {
            $problems = ($problems | append $"($cell.cell_id) ($name) has an OCM_TIMEOUT line")
        }
    }
    let image_key = $"($prefix)_REGISTRY_IMAGE"
    let want_ref = (registry-ref $cell $role)
    if ($stack_env | get --optional $image_key | default "") != $want_ref {
        $problems = ($problems | append $"($cell.cell_id) ($image_key) does not match the bundle slot")
    }
    for key in [
        $"($prefix)_REVAD_REGISTRY_DRIVER"
        $"($prefix)_REVAD_NATS_ADDRESS"
        $"($prefix)_REVAD_NATS_BUCKET"
        $"($prefix)_REVAD_NATS_TTL"
        $"($prefix)_REVAD_OCM_TIMEOUT"
        $"($prefix)_REVAD_ALLOWED_FEDERATION_CIDRS"
    ] {
        if not ($key in ($stack_env | columns)) {
            $problems = ($problems | append $"($cell.cell_id) stack.env missing ($key)")
        }
    }
    $problems
}

def check-unresolved [cell: record, overlay: record, stack_env: record] {
    let ymls = (glob ($overlay.compose_d | path join "*.yml"))
    let texts = ($ymls | append $overlay.base_yml | each {|path| open --raw $path} | str join "\n")
    let keys = ($stack_env | columns)
    let missing = (brace-names $texts | where {|name| not ($name in $keys)})
    if ($missing | is-empty) {
        []
    } else {
        [$"($cell.cell_id) unresolved compose vars: ($missing | str join ", ")"]
    }
}

def check-cell [cell: record, root: string, topology: record] {
    let exec_id = (fresh-exec-id)
    let artifacts = ($nu.temp-dir | path join $"ocmts-topo-($exec_id)")
    let outcome = (try {
        mkdir $artifacts
        let overlay = (write-compose-overlays
            $cell.flow_id
            $cell.sender_platform
            $cell.artifact_name
            $exec_id
            "sender-image:test"
            "cypress:test"
            "cypress-dev:test"
            "mariadb:test"
            "valkey:test"
            $"cypress/e2e/($cell.flow_id)/index.cy.ts"
            $cell.browser
            false
            $root
            $artifacts
            $cell.receiver_platform
            "receiver-image:test"
            "mitm:test"
            $cell.sender_version
            $cell.receiver_version
            {}
            {}
            --cell-id $cell.cell_id)
        let stack_env = (env-map $overlay.env_file)
        let roles = (cernbox-roles $cell)
        mut problems = (check-copied-cookbook $cell "sender" $overlay $root $topology)
        if $cell.is_two_party {
            $problems = ($problems | append (check-copied-cookbook $cell "receiver" $overlay $root $topology))
        }
        for role in $roles {
            $problems = ($problems | append (check-cernbox-party $cell $role $overlay $stack_env))
        }
        if ($roles | is-empty) {
            let text = (open --raw $overlay.env_file)
            if ($text | str contains "REVAD_REGISTRY") or ($text | str contains "REGISTRY_IMAGE") or ($text | str contains "REVAD_NATS") {
                $problems = ($problems | append $"($cell.cell_id) non-CERNBox stack.env gained registry lines")
            }
            let sender_txt = (open --raw ($overlay.compose_d | path join "sender.yml"))
            if ($sender_txt | str contains "revad-registry") {
                $problems = ($problems | append $"($cell.cell_id) non-CERNBox sender cookbook gained a registry")
            }
            if $cell.is_two_party {
                let receiver_txt = (open --raw ($overlay.compose_d | path join "receiver.yml"))
                if ($receiver_txt | str contains "revad-registry") {
                    $problems = ($problems | append $"($cell.cell_id) non-CERNBox receiver cookbook gained a registry")
                }
            }
        }
        $problems = ($problems | append (check-unresolved $cell $overlay $stack_env))
        if ($roles | length) == 2 {
            let sender_host = ((open ($overlay.compose_d | path join "sender.yml")).services | get sender-revad-registry | get hostname)
            let receiver_host = ((open ($overlay.compose_d | path join "receiver.yml")).services | get receiver-revad-registry | get hostname)
            if $sender_host == $receiver_host {
                $problems = ($problems | append $"($cell.cell_id) pair brokers share a hostname")
            }
        }
        $problems
    } catch {|err|
        [$"($cell.cell_id) render failed: ($err.msg)"]
    })
    drop-run $exec_id $artifacts
    $outcome
}

def test-cernbox-matrix-compose-shapes [] {
    test-log "\n[test-cernbox-matrix-compose-shapes]"
    with-env (cernbox-image-mask) {
        let root = (repo-root)
        let topology = (load-flow-topology $root)
        let cells = (enabled-cells)
        let got_ids = ($cells | each {|cell|
            let roles = (cernbox-roles $cell)
            if ($roles | is-empty) { "" } else { $cell.cell_id }
        } | where {|id| not ($id | is-empty)} | sort)
        let shape_problems = ($cells | each {|cell| check-cell $cell $root $topology} | flatten)
        [
            (assert-eq ($cells | length) 42 "enabled matrix still has 42 cells")
            (assert-eq $got_ids ($CERNBOX_CELL_IDS | sort) "the nine CERNBox cells are unchanged")
            (assert-eq $shape_problems [] "CERNBox and non-CERNBox compose shapes")
        ]
    }
}

def mask-run-text [text: string, exec_id: string, cidr: string] {
    $text | str replace --all $exec_id "EXEC_ID" | str replace --all $cidr "EXEC_CIDR"
}

def test-second-subnet-changes-cidr-only [] {
    test-log "\n[test-second-subnet-changes-cidr-only]"
    with-env (cernbox-image-mask) {
        let root = (repo-root)
        let cell = (enabled-cells | where {|row| $row.cell_id == "contact-token__cernbox-v11__cernbox-v11"} | first)
        let id_a = "20260101t000000-01020304"
        let id_b = "20260101t000000-aabbccdd"
        let cidr_a = (execution-cidr $id_a)
        let cidr_b = (execution-cidr $id_b)
        let run_a = (render-cell $cell $id_a $root)
        let run_b = (render-cell $cell $id_b $root)
        let env_a = (open --raw $run_a.overlay.env_file)
        let env_b = (open --raw $run_b.overlay.env_file)
        let exec_a = (open --raw ($run_a.overlay.compose_d | path join "exec.yml"))
        let exec_b = (open --raw ($run_b.overlay.compose_d | path join "exec.yml"))
        let sender_a = (open --raw ($run_a.overlay.compose_d | path join "sender.yml"))
        let sender_b = (open --raw ($run_b.overlay.compose_d | path join "sender.yml"))
        let receiver_a = (open --raw ($run_a.overlay.compose_d | path join "receiver.yml"))
        let receiver_b = (open --raw ($run_b.overlay.compose_d | path join "receiver.yml"))
        let cidr_line = {|cidr|
            "SENDER_REVAD_ALLOWED_FEDERATION_CIDRS=" + ([$cidr] | to json --raw)
        }
        let results = [
            (assert-truthy ($cidr_a != $cidr_b) "the two execution ids allocate different CIDRs")
            (assert-eq $sender_a $sender_b "sender cookbook bytes ignore the subnet")
            (assert-eq $receiver_a $receiver_b "receiver cookbook bytes ignore the subnet")
            (assert-eq (mask-run-text $env_a $id_a $cidr_a) (mask-run-text $env_b $id_b $cidr_b)
                "stack.env differs only by execution id and CIDR")
            (assert-eq (mask-run-text $exec_a $id_a $cidr_a) (mask-run-text $exec_b $id_b $cidr_b)
                "exec.yml differs only by execution id and CIDR")
            (assert-string-contains $env_a (do $cidr_line $cidr_a) "first render records its sender CIDR")
            (assert-string-contains $env_b (do $cidr_line $cidr_b) "second render records its sender CIDR")
            (assert-truthy (not ($env_a | str contains $cidr_b)) "first stack.env omits the other CIDR")
            (assert-string-contains $exec_a $cidr_a "first exec.yml records its subnet")
            (assert-string-contains $exec_b $cidr_b "second exec.yml records its subnet")
        ]
        drop-run $id_a $run_a.artifacts
        drop-run $id_b $run_b.artifacts
        $results
    }
}

def main [] {
    let results = ([]
        | append (test-login-is-one-party)
        | append (test-share-with-is-two-party)
        | append (test-assert-topology-matches-ok)
        | append (test-assert-topology-mismatch-errors)
        | append (test-compute-cell-login-one-party-ok)
        | append (test-compute-cell-login-with-receiver-errors)
        | append (test-compute-cell-share-with-two-party-ok)
        | append (test-compute-cell-share-with-no-receiver-errors)
        | append (test-cernbox-matrix-compose-shapes)
        | append (test-second-subnet-changes-cidr-only)
    )
    run-suite "matrix/topology" $SUITE_PATH $results
}
