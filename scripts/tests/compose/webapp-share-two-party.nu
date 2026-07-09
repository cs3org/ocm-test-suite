# webapp-share two-party topology: real sender-hub service, hub env contract,
# runner/platform dependencies, and default actor resolution.
# Run: nu scripts/tests/compose/webapp-share-two-party.nu

const SUITE_PATH = path self
const FIXTURE_EXEC_ID = "20260101t000000-aabbcc01"

use ../../lib/compose/topology-two-party.nu [
    write-two-party-env
    write-two-party-overlays
    patch-webapp-share-sender-yml
]
use ../../lib/domain/core/ocmts-root.nu [get-ocmts-root]
use ../../lib/images/resolve.nu [resolve-images resolve-receiver-images]
use ../../lib/run/execution-id.nu [execution-temp-path]
use ../../lib/tests/assert.nu *
use ../../lib/tests/runner.nu [run-suite]

const HUB_HOST = "jupyterhub1.docker"
const HUB_IMAGE = "ghcr.io/mahdibaghbani/containers/jupyterhub:webapp-share"
const HUB_CRYPT_KEY = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
const HUB_API_KEY = "ocmts-webapp-share-hub-api-key"
const HUB_OCM_API_KEY = "ocmts-webapp-share-hub-ocm-api-key"

def read-stack-env-lines [env_file: string] {
    (open $env_file | lines | each {|l| ($l | str trim)} | where {|l| not ($l | is-empty)})
}

def read-text [path: string] {
    open -r $path
}

def is-compose-top-level-service-line [line: string] {
    not (($line | parse --regex '^  [^\s].+:$' | is-empty))
}

def extract-compose-service-block [src: string, service: string] {
    let marker = $"  ($service):"
    let lines = ($src | lines)
    let start = ($lines | enumerate | where {|e| $e.item == $marker} | first)
    if ($start == null) {
        return null
    }
    let tail = ($lines | skip ($start.index + 1))
    let next = ($tail | enumerate | where {|e| (is-compose-top-level-service-line $e.item)} | first)
    let end = if ($next == null) { ($tail | length) } else { $next.index }
    $tail | take $end | str join (char newline)
}

def cleanup-overlay-artifacts [artifacts_base: string, execution_id: string] {
    rm -rf $artifacts_base
    rm -rf (execution-temp-path $execution_id)
}

def make-webapp-share-overlay [
    root: string,
    artifacts_base: string,
    --receiver-platform: string = "cernbox",
    --receiver-version: string = "v11",
    --artifact-name: string = "cell-webapp-share-nc-v35",
] {
    let matrix_key = $"webapp-share__nextcloud__($receiver_platform)"
    let sender_imgs = (
        resolve-images "nextcloud" "v35"
            --matrix-key $matrix_key --flow-id "webapp-share"
    )
    let recv_imgs = (
        resolve-receiver-images $receiver_platform $receiver_version
            --matrix-key $matrix_key --flow-id "webapp-share"
    )
    (write-two-party-overlays
        "webapp-share" "nextcloud" $receiver_platform $artifact_name $FIXTURE_EXEC_ID
        $sender_imgs.platform $recv_imgs.platform "mitmproxy:test"
        $sender_imgs.cypress_ci $sender_imgs.cypress_dev
        $sender_imgs.mariadb $sender_imgs.valkey
        "cypress/e2e/webapp-share/index.cy.ts" "chrome" false
        $root $artifacts_base
        "v35" $receiver_version
    )
}

def test-webapp-share-overlay-sender-hub-service [] {
    test-log "\n[test-webapp-share-overlay-sender-hub-service]"
    let root = (get-ocmts-root)
    let artifacts_base = ($nu.temp-dir | path join $"webapp-share-overlay-(random uuid)")
    mkdir ($artifacts_base | path join "compose" "inputs")
    let overlay = (make-webapp-share-overlay $root $artifacts_base)
    let hub_yml = (read-text ($overlay.compose_d | path join "webapp-hub.yml"))
    let source_hub = (read-text ($root | path join "config/compose/cookbooks/nextcloud.webapp-hub.yml"))
    let results = [
        (assert-list-contains $overlay.base_overlay_fnames "webapp-hub.yml"
            "base_overlay_fnames includes webapp-hub.yml for webapp-share")
        (assert-string-contains $hub_yml "  sender-hub:"
            "webapp-hub.yml defines sender-hub service")
        (assert-eq $hub_yml $source_hub
            "webapp-hub.yml mirrors nextcloud.webapp-hub.yml cookbook")
        (assert-truthy (($overlay.compose_d | path join "webapp-hub.yml") | path exists)
            "compose_d contains webapp-hub.yml overlay")
    ]
    cleanup-overlay-artifacts $artifacts_base $FIXTURE_EXEC_ID
    $results
}

def test-webapp-share-hub-host-alias-on-sender-hub [] {
    test-log "\n[test-webapp-share-hub-host-alias-on-sender-hub]"
    let root = (get-ocmts-root)
    let artifacts_base = ($nu.temp-dir | path join $"webapp-share-alias-(random uuid)")
    mkdir ($artifacts_base | path join "compose" "inputs")
    let overlay = (make-webapp-share-overlay $root $artifacts_base)
    let sender_yml = (read-text ($overlay.compose_d | path join "sender.yml"))
    let hub_yml = (read-text ($overlay.compose_d | path join "webapp-hub.yml"))
    let sender_block = (extract-compose-service-block $sender_yml "sender")
    let hub_block = (extract-compose-service-block $hub_yml "sender-hub")
    let results = [
        (assert-not-null $sender_block "sender service block exists")
        (assert-not-null $hub_block "sender-hub service block exists")
        (assert-truthy (not ($sender_block | str contains $HUB_HOST))
            "jupyterhub1.docker is not aliased on sender service")
        (assert-string-contains $hub_block "${SENDER_HUB_HOST}"
            "sender-hub network alias uses SENDER_HUB_HOST from stack.env")
        (assert-string-contains $sender_block "JUPYTER_HOST=${SENDER_HUB_HOST}"
            "sender.yml references JUPYTER_HOST from stack.env")
    ]
    cleanup-overlay-artifacts $artifacts_base $FIXTURE_EXEC_ID
    $results
}

def test-webapp-share-stack-env-hub-contract [] {
    test-log "\n[test-webapp-share-stack-env-hub-contract]"
    let root = (get-ocmts-root)
    let artifacts_base = ($nu.temp-dir | path join $"webapp-share-env-(random uuid)")
    mkdir ($artifacts_base | path join "compose" "inputs")
    let overlay = (make-webapp-share-overlay $root $artifacts_base)
    let lines = (read-stack-env-lines $overlay.env_file)
    let no_proxy_line = ($lines | where {|l| $l | str starts-with "SENDER_NO_PROXY="} | first)
    let results = [
        (assert-list-contains $lines $"SENDER_HUB_HOST=($HUB_HOST)"
            "stack.env sets SENDER_HUB_HOST=jupyterhub1.docker")
        (assert-list-contains $lines $"SENDER_HUB_IMAGE=($HUB_IMAGE)"
            "stack.env has SENDER_HUB_IMAGE from hub bundle slot")
        (assert-list-contains $lines "SENDER_TRUSTED_DOMAINS=nextcloud1.docker jupyterhub1.docker"
            "stack.env sets sender and hub hosts in SENDER_TRUSTED_DOMAINS")
        (assert-list-contains $lines $"SENDER_HUB_CRYPT_KEY=($HUB_CRYPT_KEY)"
            "stack.env has deterministic SENDER_HUB_CRYPT_KEY")
        (assert-list-contains $lines $"SENDER_HUB_API_KEY=($HUB_API_KEY)"
            "stack.env has deterministic SENDER_HUB_API_KEY")
        (assert-list-contains $lines $"SENDER_HUB_OCM_API_KEY=($HUB_OCM_API_KEY)"
            "stack.env has deterministic SENDER_HUB_OCM_API_KEY")
        (assert-not-null $no_proxy_line "SENDER_NO_PROXY line present")
        (assert-truthy (not (($no_proxy_line | str replace "SENDER_NO_PROXY=" "") | str contains $HUB_HOST))
            "hub host is absent from SENDER_NO_PROXY")
        (assert-string-contains ($no_proxy_line | str replace "SENDER_NO_PROXY=" "") "sender-hub"
            "sender-hub compose service name is in SENDER_NO_PROXY")
    ]
    cleanup-overlay-artifacts $artifacts_base $FIXTURE_EXEC_ID
    $results
}

def test-webapp-share-runner-depends-on-sender-hub [] {
    test-log "\n[test-webapp-share-runner-depends-on-sender-hub]"
    let root = (get-ocmts-root)
    let artifacts_base = ($nu.temp-dir | path join $"webapp-share-runner-(random uuid)")
    mkdir ($artifacts_base | path join "compose" "inputs")
    let overlay = (make-webapp-share-overlay $root $artifacts_base)
    let runner_ci = (read-text ($overlay.compose_d | path join "runner-ci.yml"))
    let runner_dev = (read-text ($overlay.compose_d | path join "runner-dev.yml"))
    let cypress_block = (extract-compose-service-block $runner_ci "cypress")
    let dev_block = (extract-compose-service-block $runner_dev "cypress_dev")
    let results = [
        (assert-not-null $cypress_block "runner-ci cypress block exists")
        (assert-not-null $dev_block "runner-dev cypress_dev block exists")
        (assert-string-contains $cypress_block "sender-hub:"
            "runner-ci depends_on sender-hub")
        (assert-string-contains $cypress_block "condition: service_healthy"
            "runner-ci uses service_healthy for dependencies")
        (assert-string-contains $dev_block "sender-hub:"
            "runner-dev depends_on sender-hub")
    ]
    cleanup-overlay-artifacts $artifacts_base $FIXTURE_EXEC_ID
    $results
}

def test-webapp-share-oauth-handoff-wiring [] {
    test-log "\n[test-webapp-share-oauth-handoff-wiring]"
    let root = (get-ocmts-root)
    let artifacts_base = ($nu.temp-dir | path join $"webapp-share-oauth-(random uuid)")
    mkdir ($artifacts_base | path join "compose" "inputs")
    let overlay = (make-webapp-share-overlay $root $artifacts_base)
    let sender_yml = (read-text ($overlay.compose_d | path join "sender.yml"))
    let hub_yml = (read-text ($overlay.compose_d | path join "webapp-hub.yml"))
    let sender_block = (extract-compose-service-block $sender_yml "sender")
    let hub_block = (extract-compose-service-block $hub_yml "sender-hub")
    let handoff_dir = ($artifacts_base | path join "oauth-handoff")
    let results = [
        (assert-string-contains $sender_block "INTEGRATION_JUPYTERHUB_OAUTH_ENV_FILE=/oauth-handoff/oauth.env"
            "sender writes OAuth creds to the shared handoff file")
        (assert-string-contains $sender_block "/oauth-handoff"
            "sender mounts the shared oauth-handoff volume")
        (assert-string-contains $hub_block "NEXTCLOUD_OAUTH_ENV_FILE=/oauth-handoff/oauth.env"
            "sender-hub reads OAuth creds from the shared handoff file")
        (assert-string-contains $hub_block "oauth-handoff:/oauth-handoff:ro"
            "sender-hub mounts the shared oauth-handoff volume read-only")
        (assert-string-contains $hub_block "/hub/health"
            "sender-hub healthcheck probes the hub health endpoint")
        (assert-truthy (not ($hub_block | str contains "curl "))
            "sender-hub healthcheck does not depend on curl")
        (assert-truthy ($handoff_dir | path exists)
            "oauth-handoff shared dir is created under artifacts")
    ]
    cleanup-overlay-artifacts $artifacts_base $FIXTURE_EXEC_ID
    $results
}

def test-webapp-share-actor-resolution-defaults [] {
    test-log "\n[test-webapp-share-actor-resolution-defaults]"
    let root = (get-ocmts-root)
    let artifacts_base = ($nu.temp-dir | path join $"webapp-share-actors-(random uuid)")
    mkdir ($artifacts_base | path join "compose" "inputs")
    let overlay = (make-webapp-share-overlay $root $artifacts_base)
    let lines = (read-stack-env-lines $overlay.env_file)
    let results = [
        (assert-list-contains $lines "CYPRESS_sender_username=michiel"
            "default sender actor michiel resolved without overrides")
        (assert-list-contains $lines "CYPRESS_sender_password=michiel"
            "default sender password resolved without overrides")
        (assert-list-contains $lines "CYPRESS_receiver_username=marie"
            "default receiver actor marie resolved without overrides")
        (assert-list-contains $lines "CYPRESS_receiver_password=radioactivity"
            "default receiver password resolved from cernbox actor marie")
    ]
    cleanup-overlay-artifacts $artifacts_base $FIXTURE_EXEC_ID
    $results
}

def test-webapp-share-nc-nc-reuses-sender-hub-topology [] {
    test-log "\n[test-webapp-share-nc-nc-reuses-sender-hub-topology]"
    let root = (get-ocmts-root)
    let artifacts_cb = ($nu.temp-dir | path join $"webapp-share-nc-cb-(random uuid)")
    let artifacts_nc = ($nu.temp-dir | path join $"webapp-share-nc-nc-(random uuid)")
    mkdir ($artifacts_cb | path join "compose" "inputs")
    mkdir ($artifacts_nc | path join "compose" "inputs")
    let overlay_cb = (make-webapp-share-overlay $root $artifacts_cb)
    let overlay_nc = (
        make-webapp-share-overlay $root $artifacts_nc
            --receiver-platform "nextcloud" --receiver-version "v35"
            --artifact-name "cell-webapp-share-nc-v35-nc"
    )
    let hub_cb = (read-text ($overlay_cb.compose_d | path join "webapp-hub.yml"))
    let hub_nc = (read-text ($overlay_nc.compose_d | path join "webapp-hub.yml"))
    let runner_nc = (read-text ($overlay_nc.compose_d | path join "runner-ci.yml"))
    let source_hub = (read-text ($root | path join "config/compose/cookbooks/nextcloud.webapp-hub.yml"))
    let results = [
        (assert-eq $hub_nc $hub_cb
            "NC->NC webapp-hub.yml matches NC->CB sender-hub overlay shape")
        (assert-eq $hub_nc $source_hub
            "NC->NC webapp-hub.yml mirrors nextcloud.webapp-hub.yml cookbook")
        (assert-list-contains $overlay_nc.base_overlay_fnames "webapp-hub.yml"
            "NC->NC base_overlay_fnames includes webapp-hub.yml")
        (assert-string-contains $runner_nc "sender-hub:"
            "NC->NC runner-ci depends_on sender-hub")
        (assert-truthy (($overlay_nc.compose_d | path join "webapp-hub.yml") | path exists)
            "NC->NC compose_d contains webapp-hub.yml overlay")
    ]
    cleanup-overlay-artifacts $artifacts_cb $FIXTURE_EXEC_ID
    cleanup-overlay-artifacts $artifacts_nc $FIXTURE_EXEC_ID
    $results
}

def webapp-share-image-override-env-mask [] {
    [
        OCMTS_NEXTCLOUD_V35_WEBAPP_SHARE_SENDER_IMAGE
        OCMTS_NEXTCLOUD_V35_WEBAPP_SHARE_RECEIVER_IMAGE
        OCMTS_NEXTCLOUD_V35_WEBAPP_SHARE_IMAGE
        OCMTS_NEXTCLOUD_V35_SENDER_IMAGE
        OCMTS_NEXTCLOUD_V35_RECEIVER_IMAGE
        OCMTS_NEXTCLOUD_V35_IMAGE
    ]
    | reduce --fold {} {|k, acc|
        if $k in $env { $acc | upsert $k null } else { $acc }
    }
}

def test-webapp-share-nc-nc-local-image-override-compose-boundary [] {
    test-log "\n[test-webapp-share-nc-nc-local-image-override-compose-boundary]"
    let root = (get-ocmts-root)
    let artifacts_base = ($nu.temp-dir | path join $"webapp-share-nc-nc-img-(random uuid)")
    mkdir ($artifacts_base | path join "compose" "inputs")
    let sender_role = "localhost/ocmts/nextcloud-v35-webapp-share-sender:local"
    let receiver_role = "localhost/ocmts/nextcloud-v35-webapp-share-receiver:local"
    let overlay = (
        with-env (webapp-share-image-override-env-mask | merge {
            OCMTS_NEXTCLOUD_V35_WEBAPP_SHARE_SENDER_IMAGE: $sender_role
            OCMTS_NEXTCLOUD_V35_WEBAPP_SHARE_RECEIVER_IMAGE: $receiver_role
        }) {
            (make-webapp-share-overlay $root $artifacts_base --receiver-platform "nextcloud" --receiver-version "v35" --artifact-name "cell-webapp-share-nc-v35-nc")
        }
    )
    let lines = (read-stack-env-lines $overlay.env_file)
    let sender_yml = (read-text ($overlay.compose_d | path join "sender.yml"))
    let receiver_yml = (read-text ($overlay.compose_d | path join "receiver.yml"))
    let sender_block = (extract-compose-service-block $sender_yml "sender")
    let receiver_block = (extract-compose-service-block $receiver_yml "receiver")
    let results = [
        (assert-list-contains $lines $"SENDER_IMAGE=($sender_role)"
            "NC->NC stack.env carries resolved sender image override")
        (assert-list-contains $lines $"RECEIVER_IMAGE=($receiver_role)"
            "NC->NC stack.env carries resolved receiver image override")
        (assert-string-contains $sender_yml "${SENDER_IMAGE}"
            "NC->NC sender.yml keeps SENDER_IMAGE placeholder from cookbook")
        (assert-string-contains $receiver_yml "${RECEIVER_IMAGE}"
            "NC->NC receiver.yml keeps RECEIVER_IMAGE placeholder from cookbook")
        (assert-not-null $sender_block "NC->NC sender service block exists")
        (assert-not-null $receiver_block "NC->NC receiver service block exists")
        (assert-string-contains $sender_block "image: ${SENDER_IMAGE}"
            "NC->NC sender service consumes SENDER_IMAGE from stack.env")
        (assert-string-contains $receiver_block "image: ${RECEIVER_IMAGE}"
            "NC->NC receiver service consumes RECEIVER_IMAGE from stack.env")
    ]
    cleanup-overlay-artifacts $artifacts_base $FIXTURE_EXEC_ID
    $results
}

def test-webapp-share-nc-nc-receiver-actor-defaults [] {
    test-log "\n[test-webapp-share-nc-nc-receiver-actor-defaults]"
    let root = (get-ocmts-root)
    let artifacts_base = ($nu.temp-dir | path join $"webapp-share-nc-nc-actors-(random uuid)")
    mkdir ($artifacts_base | path join "compose" "inputs")
    let overlay = (
        make-webapp-share-overlay $root $artifacts_base
            --receiver-platform "nextcloud" --receiver-version "v35"
            --artifact-name "cell-webapp-share-nc-v35-nc"
    )
    let lines = (read-stack-env-lines $overlay.env_file)
    let results = [
        (assert-list-contains $lines "CYPRESS_sender_username=michiel"
            "NC->NC default sender actor michiel resolved without overrides")
        (assert-list-contains $lines "CYPRESS_sender_password=michiel"
            "NC->NC default sender password resolved without overrides")
        (assert-list-contains $lines "CYPRESS_receiver_username=marie"
            "NC->NC default receiver actor marie resolved without overrides")
        (assert-list-contains $lines "CYPRESS_receiver_password=marie"
            "NC->NC receiver password resolved from nextcloud actor marie")
        (assert-truthy (
            not ($lines | any {|l| $l == "CYPRESS_receiver_password=radioactivity"})
        ) "NC->NC receiver password is not the cernbox marie password")
    ]
    cleanup-overlay-artifacts $artifacts_base $FIXTURE_EXEC_ID
    $results
}

def test-share-with-unchanged-no-sender-hub [] {
    test-log "\n[test-share-with-unchanged-no-sender-hub]"
    let root = (get-ocmts-root)
    let artifacts_base = ($nu.temp-dir | path join $"share-with-regression-(random uuid)")
    mkdir ($artifacts_base | path join "compose" "inputs")
    let sender_imgs = (
        resolve-images "nextcloud" "v32"
            --matrix-key "share-with__nextcloud__nextcloud" --flow-id "share-with"
    )
    let recv_imgs = (
        resolve-receiver-images "nextcloud" "v32"
            --matrix-key "share-with__nextcloud__nextcloud" --flow-id "share-with"
    )
    let overlay = (write-two-party-overlays
        "share-with" "nextcloud" "nextcloud" "cell-share-nc-v32" $FIXTURE_EXEC_ID
        $sender_imgs.platform $recv_imgs.platform "mitmproxy:test"
        $sender_imgs.cypress_ci $sender_imgs.cypress_dev
        $sender_imgs.mariadb $sender_imgs.valkey
        "cypress/e2e/share-with/index.cy.ts" "chrome" false
        $root $artifacts_base
        "v32" "v32"
    )
    let lines = (read-stack-env-lines $overlay.env_file)
    let sender_yml = (read-text ($overlay.compose_d | path join "sender.yml"))
    let sender_block = (extract-compose-service-block $sender_yml "sender")
    let runner_ci = (read-text ($overlay.compose_d | path join "runner-ci.yml"))
    let hub_overlay = ($overlay.compose_d | path join "webapp-hub.yml")
    let results = [
        (assert-truthy (not ($hub_overlay | path exists))
            "share-with does not copy webapp-hub overlay")
        (assert-truthy (not ($overlay.base_overlay_fnames | any {|f| $f == "webapp-hub.yml"}))
            "share-with base_overlay_fnames omits webapp-hub.yml")
        (assert-not-null $sender_block "share-with sender service block exists")
        (assert-truthy (not ($sender_block | str contains "JUPYTER_HOST"))
            "share-with sender overlay omits JUPYTER_HOST")
        (assert-truthy (not ($sender_block | str contains "SENDER_HUB_HOST"))
            "share-with sender overlay omits SENDER_HUB_HOST substitution")
        (assert-truthy (not ($sender_block | str contains "oauth-handoff"))
            "share-with sender overlay omits the oauth-handoff wiring")
        (assert-truthy (not (($artifacts_base | path join "oauth-handoff") | path exists))
            "share-with does not create the oauth-handoff shared dir")
        (assert-truthy (
            $lines | where {|l| $l | str starts-with "SENDER_HUB_HOST="} | is-empty
        ) "share-with stack.env omits SENDER_HUB_HOST")
        (assert-truthy (
            $lines | where {|l| $l | str starts-with "SENDER_HUB_IMAGE="} | is-empty
        ) "share-with stack.env omits SENDER_HUB_IMAGE")
        (assert-list-contains $lines "SENDER_TRUSTED_DOMAINS=nextcloud1.docker"
            "share-with stack.env sets default sender trusted domains without hub host")
        (assert-truthy (not ($runner_ci | str contains "sender-hub:"))
            "share-with runner does not depend on sender-hub")
    ]
    cleanup-overlay-artifacts $artifacts_base $FIXTURE_EXEC_ID
    $results
}

# --- patch-webapp-share-sender-yml direct unit coverage ---
# These mirror the injected line contract in topology-two-party.nu so drift in
# either place is caught. They exercise the fail-fast and idempotency paths that
# the full-generation tests above cannot reach (the real cookbook always has the
# markers and is never pre-patched).
const PATCH_NO_PROXY_MARKER = '      - NO_PROXY=${SENDER_NO_PROXY}'
const PATCH_ACTORS_VOL_MARKER = '      - ${OCMTS_ROOT}/config/actors:/ocmts/actors:ro'
const PATCH_JUPYTER_ENV_LINE = '      - JUPYTER_HOST=${SENDER_HUB_HOST}'
const PATCH_OAUTH_ENV_LINE = '      - INTEGRATION_JUPYTERHUB_OAUTH_ENV_FILE=/oauth-handoff/oauth.env'
const PATCH_OAUTH_VOL_LINE = '      - ${OCMTS_ARTIFACTS_BASE}/oauth-handoff:/oauth-handoff'

def did-throw [cl: closure] {
    try { do $cl; false } catch { true }
}

def write-sender-fixture [lines: list<string>] {
    let dir = ($nu.temp-dir | path join $"patch-sender-fixture-(random uuid)")
    mkdir $dir
    ($lines | str join (char newline)) | save --force ($dir | path join "sender.yml")
    $dir
}

def test-patch-sender-happy-and-idempotent [] {
    test-log "\n[test-patch-sender-happy-and-idempotent]"
    let dir = (write-sender-fixture [
        "services:"
        "  sender:"
        "    environment:"
        $PATCH_NO_PROXY_MARKER
        "    volumes:"
        $PATCH_ACTORS_VOL_MARKER
    ])
    let sender_path = ($dir | path join "sender.yml")
    patch-webapp-share-sender-yml $dir
    let once = (open -r $sender_path)
    # A second call must be a no-op (fully patched), not an error or a re-inject.
    patch-webapp-share-sender-yml $dir
    let twice = (open -r $sender_path)
    let results = [
        (assert-string-contains $once $PATCH_JUPYTER_ENV_LINE
            "patch injects JUPYTER_HOST env line")
        (assert-string-contains $once $PATCH_OAUTH_ENV_LINE
            "patch injects OAuth env-file line")
        (assert-string-contains $once $PATCH_OAUTH_VOL_LINE
            "patch injects OAuth handoff volume line")
        (assert-eq $twice $once
            "second patch is idempotent (no double-inject, no error)")
    ]
    rm -rf $dir
    $results
}

def test-patch-sender-marker-miss-fails [] {
    test-log "\n[test-patch-sender-marker-miss-fails]"
    # sender.yml missing the NO_PROXY marker must fail fast, not silently no-op.
    let dir = (write-sender-fixture [
        "services:"
        "  sender:"
        "    environment:"
        "      - SOME_OTHER=1"
        "    volumes:"
        $PATCH_ACTORS_VOL_MARKER
    ])
    let threw = (did-throw {|| patch-webapp-share-sender-yml $dir })
    rm -rf $dir
    [
        (assert-truthy $threw
            "patch fails fast when the NO_PROXY marker is absent (no silent no-op)")
    ]
}

def test-patch-sender-partial-fails [] {
    test-log "\n[test-patch-sender-partial-fails]"
    # Already carries JUPYTER_HOST but not the OAuth lines -> drifted/partial;
    # patch must refuse rather than corrupt the overlay.
    let dir = (write-sender-fixture [
        "services:"
        "  sender:"
        "    environment:"
        $PATCH_NO_PROXY_MARKER
        $PATCH_JUPYTER_ENV_LINE
        "    volumes:"
        $PATCH_ACTORS_VOL_MARKER
    ])
    let threw = (did-throw {|| patch-webapp-share-sender-yml $dir })
    rm -rf $dir
    [
        (assert-truthy $threw
            "patch refuses to re-patch a partially-patched (drifted) overlay")
    ]
}

def main [] {
    test-log "=== compose/webapp-share-two-party Tests ==="
    let results = (
        (test-webapp-share-overlay-sender-hub-service)
        | append (test-webapp-share-hub-host-alias-on-sender-hub)
        | append (test-webapp-share-stack-env-hub-contract)
        | append (test-webapp-share-runner-depends-on-sender-hub)
        | append (test-webapp-share-oauth-handoff-wiring)
        | append (test-webapp-share-actor-resolution-defaults)
        | append (test-webapp-share-nc-nc-reuses-sender-hub-topology)
        | append (test-webapp-share-nc-nc-local-image-override-compose-boundary)
        | append (test-webapp-share-nc-nc-receiver-actor-defaults)
        | append (test-share-with-unchanged-no-sender-hub)
        | append (test-patch-sender-happy-and-idempotent)
        | append (test-patch-sender-marker-miss-fails)
        | append (test-patch-sender-partial-fails)
    ) | flatten
    run-suite "compose/webapp-share-two-party" $SUITE_PATH $results
}
