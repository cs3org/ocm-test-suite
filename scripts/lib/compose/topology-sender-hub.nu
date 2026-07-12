# Sender-hub compose overlay helpers (data-declared two-party topology).

use ../run/flow-topology.nu [flow-has-sender-hub sender-hub-config]
use ./topology-common.nu [copy-platform-cookbook]

# Deterministic hub secrets for compose substitution (dev/test only).
export const SENDER_HUB_CRYPT_KEY = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
export const SENDER_HUB_API_KEY = "ocmts-webapp-share-hub-api-key"
export const SENDER_HUB_OCM_API_KEY = "ocmts-webapp-share-hub-ocm-api-key"

# Sender.yml patch markers (shared sender cookbook; sender-hub injects after copy).
export const SENDER_HUB_NO_PROXY_MARKER = '      - NO_PROXY=${SENDER_NO_PROXY}'
export const SENDER_HUB_JUPYTER_ENV_LINE = '      - JUPYTER_HOST=${SENDER_HUB_HOST}'
export const SENDER_HUB_OAUTH_ENV_LINE = '      - INTEGRATION_JUPYTERHUB_OAUTH_ENV_FILE=/oauth-handoff/oauth.env'
export const SENDER_HUB_VOLUMES_MARKER = '      - ${OCMTS_ROOT}/config/actors:/ocmts/actors:ro'
export const SENDER_HUB_OAUTH_VOLUME_LINE = '      - ${OCMTS_ARTIFACTS_BASE}/oauth-handoff:/oauth-handoff'

# Inject JUPYTER_HOST + OAuth handoff into sender.yml. Fails on marker miss or
# partial patch; no-op when all three injected lines are already present.
export def patch-sender-hub-sender-yml [compose_d: string] {
    let sender_path = ($compose_d | path join "sender.yml")
    let src = (open --raw $sender_path)

    let has_env = ($src | str contains $SENDER_HUB_JUPYTER_ENV_LINE)
    let has_oauth_env = ($src | str contains $SENDER_HUB_OAUTH_ENV_LINE)
    let has_oauth_vol = ($src | str contains $SENDER_HUB_OAUTH_VOLUME_LINE)
    let injected_count = ([$has_env $has_oauth_env $has_oauth_vol] | where {|v| $v } | length)

    if $injected_count == 3 {
        return
    }
    if $injected_count != 0 {
        error make {
            msg: $"sender.yml at ($sender_path) is partially patched for sender-hub \(($injected_count) of 3 lines\); refusing to re-patch a drifted overlay"
        }
    }

    if not ($src | str contains $SENDER_HUB_NO_PROXY_MARKER) {
        error make {
            msg: $"sender.yml at ($sender_path) missing NO_PROXY marker; cannot inject JUPYTER_HOST/OAuth env for sender-hub"
        }
    }
    if not ($src | str contains $SENDER_HUB_VOLUMES_MARKER) {
        error make {
            msg: $"sender.yml at ($sender_path) missing actors volume marker; cannot inject OAuth handoff volume for sender-hub"
        }
    }

    let env_replacement = ([
        $SENDER_HUB_NO_PROXY_MARKER
        $SENDER_HUB_JUPYTER_ENV_LINE
        $SENDER_HUB_OAUTH_ENV_LINE
    ] | str join "\n")
    let vol_replacement = ([
        $SENDER_HUB_VOLUMES_MARKER
        $SENDER_HUB_OAUTH_VOLUME_LINE
    ] | str join "\n")
    ($src
        | str replace $SENDER_HUB_NO_PROXY_MARKER $env_replacement
        | str replace $SENDER_HUB_VOLUMES_MARKER $vol_replacement)
        | save --force $sender_path
}

def sender-hub-cookbook-service-names [
    root: string,
    sender_platform: string,
    flow_id: string,
    topology: record,
] {
    if not (flow-has-sender-hub $flow_id $topology) {
        return []
    }
    let hub_cfg = (sender-hub-config $flow_id $topology)
    let cookbook_kind = $hub_cfg.cookbook_kind
    let cookbook_path = (
        $root | path join "config/compose/cookbooks" $"($sender_platform).($cookbook_kind).yml"
    )
    if not ($cookbook_path | path exists) {
        error make {
            msg: $"sender-hub cookbook missing at ($cookbook_path) for flow '($flow_id)'"
        }
    }
    try {
        let cooked = (open $cookbook_path)
        if not ("services" in ($cooked | columns)) {
            return []
        }
        $cooked | get services | columns
    } catch {
        []
    }
}

export def sender-hub-extend-sender-no-proxy [
    sender_no_proxy: list<string>,
    flow_id: string,
    topology: record,
    root: string,
    sender_platform: string,
]: nothing -> list<string> {
    if not (flow-has-sender-hub $flow_id $topology) {
        return $sender_no_proxy
    }
    $sender_no_proxy
    | append (sender-hub-cookbook-service-names $root $sender_platform $flow_id $topology)
    | uniq
}

export def sender-hub-sender-trusted-domains [
    sender_party_host: string,
    flow_id: string,
    topology: record,
] {
    if not (flow-has-sender-hub $flow_id $topology) {
        return $sender_party_host
    }
    let hub_host = (sender-hub-config $flow_id $topology | get host)
    $"($sender_party_host) ($hub_host)"
}

export def sender-hub-stack-env-lines [flow_id: string, topology: record] {
    let hub_cfg = (sender-hub-config $flow_id $topology)
    let hub_host = $hub_cfg.host
    [
        $"SENDER_HUB_HOST=($hub_host)"
        $"SENDER_HUB_CRYPT_KEY=($SENDER_HUB_CRYPT_KEY)"
        $"SENDER_HUB_API_KEY=($SENDER_HUB_API_KEY)"
        $"SENDER_HUB_OCM_API_KEY=($SENDER_HUB_OCM_API_KEY)"
    ]
}

export def sender-hub-runner-depends-on-lines [] {
    [
        "      sender-hub:"
        "        condition: service_healthy"
    ]
}

export def apply-sender-hub-compose-overlays [
    root: string,
    flow_id: string,
    topology: record,
    sender_platform: string,
    compose_d: string,
    artifacts_base: string,
] {
    if not (flow-has-sender-hub $flow_id $topology) {
        return
    }
    let hub_cfg = (sender-hub-config $flow_id $topology)
    let expected_overlay = $"($hub_cfg.cookbook_kind).yml"
    if $hub_cfg.overlay_fname != $expected_overlay {
        error make {
            msg: $"sender-hub declaration for flow '($flow_id)' is inconsistent: overlay_fname '($hub_cfg.overlay_fname)' must equal '($expected_overlay)' \(derived from cookbook_kind '($hub_cfg.cookbook_kind)'\)"
        }
    }
    patch-sender-hub-sender-yml $compose_d
    copy-platform-cookbook $root $sender_platform $hub_cfg.cookbook_kind $compose_d
    mkdir ($artifacts_base | path join "oauth-handoff")
}

export def sender-hub-base-overlay-fnames [
    base_overlay_fnames: list<string>,
    flow_id: string,
    topology: record,
] {
    if not (flow-has-sender-hub $flow_id $topology) {
        return $base_overlay_fnames
    }
    let overlay_fname = (sender-hub-config $flow_id $topology | get overlay_fname)
    $base_overlay_fnames | append $overlay_fname
}
