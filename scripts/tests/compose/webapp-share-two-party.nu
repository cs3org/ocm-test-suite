# webapp-share two-party topology: real sender-hub service, hub env contract,
# runner/platform dependencies, and default actor resolution.
# Run: nu scripts/tests/compose/webapp-share-two-party.nu

const SUITE_PATH = path self

use ../../lib/compose/topology-webapp-share.nu [
    WEBAPP_SHARE_HUB_API_KEY
    WEBAPP_SHARE_HUB_CRYPT_KEY
    WEBAPP_SHARE_HUB_OCM_API_KEY
    WEBAPP_SHARE_SENDER_HUB_HOST
]
use ../../lib/domain/core/ocmts-root.nu [get-ocmts-root]
use ../../lib/tests/assert.nu *
use ../../lib/tests/runner.nu [run-suite]
use ./_webapp-share-overlay-fixtures.nu [
    FIXTURE_EXEC_ID
    read-stack-env-lines
    read-text
    extract-compose-service-block
    cleanup-overlay-artifacts
    make-webapp-share-overlay
]

const HUB_HOST = $WEBAPP_SHARE_SENDER_HUB_HOST
const HUB_IMAGE = "ghcr.io/mahdibaghbani/containers/jupyterhub:webapp-share"
const HUB_CRYPT_KEY = $WEBAPP_SHARE_HUB_CRYPT_KEY
const HUB_API_KEY = $WEBAPP_SHARE_HUB_API_KEY
const HUB_OCM_API_KEY = $WEBAPP_SHARE_HUB_OCM_API_KEY

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
    ) | flatten
    run-suite "compose/webapp-share-two-party" $SUITE_PATH $results
}
