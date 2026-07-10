# webapp-share compose overlay helpers (two-party sender-hub topology).

use ../run/flow-ids.nu [is-webapp-share-flow]
use ./topology-common.nu [copy-platform-cookbook]

export const WEBAPP_SHARE_SENDER_HUB_HOST = "jupyterhub1.docker"
export const WEBAPP_SHARE_HUB_OVERLAY_FNAME = "webapp-hub.yml"

# Deterministic hub secrets for compose substitution (dev/test only).
export const WEBAPP_SHARE_HUB_CRYPT_KEY = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
export const WEBAPP_SHARE_HUB_API_KEY = "ocmts-webapp-share-hub-api-key"
export const WEBAPP_SHARE_HUB_OCM_API_KEY = "ocmts-webapp-share-hub-ocm-api-key"

# Sender.yml patch markers (shared sender cookbook; webapp-share injects after copy).
export const WEBAPP_SHARE_SENDER_NO_PROXY_MARKER = '      - NO_PROXY=${SENDER_NO_PROXY}'
export const WEBAPP_SHARE_SENDER_JUPYTER_ENV_LINE = '      - JUPYTER_HOST=${SENDER_HUB_HOST}'
export const WEBAPP_SHARE_SENDER_OAUTH_ENV_LINE = '      - INTEGRATION_JUPYTERHUB_OAUTH_ENV_FILE=/oauth-handoff/oauth.env'
export const WEBAPP_SHARE_SENDER_VOLUMES_MARKER = '      - ${OCMTS_ROOT}/config/actors:/ocmts/actors:ro'
export const WEBAPP_SHARE_SENDER_OAUTH_VOLUME_LINE = '      - ${OCMTS_ARTIFACTS_BASE}/oauth-handoff:/oauth-handoff'

# Inject JUPYTER_HOST + OAuth handoff into sender.yml. Fails on marker miss or
# partial patch; no-op when all three injected lines are already present.
export def patch-webapp-share-sender-yml [compose_d: string] {
    let sender_path = ($compose_d | path join "sender.yml")
    let src = (open --raw $sender_path)

    let has_env = ($src | str contains $WEBAPP_SHARE_SENDER_JUPYTER_ENV_LINE)
    let has_oauth_env = ($src | str contains $WEBAPP_SHARE_SENDER_OAUTH_ENV_LINE)
    let has_oauth_vol = ($src | str contains $WEBAPP_SHARE_SENDER_OAUTH_VOLUME_LINE)
    let injected_count = ([$has_env $has_oauth_env $has_oauth_vol] | where {|v| $v } | length)

    if $injected_count == 3 {
        return
    }
    if $injected_count != 0 {
        error make {
            msg: $"sender.yml at ($sender_path) is partially patched for webapp-share \(($injected_count) of 3 lines\); refusing to re-patch a drifted overlay"
        }
    }

    if not ($src | str contains $WEBAPP_SHARE_SENDER_NO_PROXY_MARKER) {
        error make {
            msg: $"sender.yml at ($sender_path) missing NO_PROXY marker; cannot inject JUPYTER_HOST/OAuth env for webapp-share"
        }
    }
    if not ($src | str contains $WEBAPP_SHARE_SENDER_VOLUMES_MARKER) {
        error make {
            msg: $"sender.yml at ($sender_path) missing actors volume marker; cannot inject OAuth handoff volume for webapp-share"
        }
    }

    let env_replacement = ([
        $WEBAPP_SHARE_SENDER_NO_PROXY_MARKER
        $WEBAPP_SHARE_SENDER_JUPYTER_ENV_LINE
        $WEBAPP_SHARE_SENDER_OAUTH_ENV_LINE
    ] | str join "\n")
    let vol_replacement = ([
        $WEBAPP_SHARE_SENDER_VOLUMES_MARKER
        $WEBAPP_SHARE_SENDER_OAUTH_VOLUME_LINE
    ] | str join "\n")
    ($src
        | str replace $WEBAPP_SHARE_SENDER_NO_PROXY_MARKER $env_replacement
        | str replace $WEBAPP_SHARE_SENDER_VOLUMES_MARKER $vol_replacement)
        | save --force $sender_path
}

def webapp-hub-cookbook-service-names [root: string, sender_platform: string] {
    let cookbook_path = ($root | path join "config/compose/cookbooks" $"($sender_platform).webapp-hub.yml")
    if not ($cookbook_path | path exists) {
        return []
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

export def webapp-share-extend-sender-no-proxy [
    sender_no_proxy: list<string>,
    flow_id: string,
    root: string,
    sender_platform: string,
]: nothing -> list<string> {
    if not (is-webapp-share-flow $flow_id) {
        return $sender_no_proxy
    }
    $sender_no_proxy
    | append (webapp-hub-cookbook-service-names $root $sender_platform)
    | uniq
}

export def webapp-share-sender-trusted-domains [sender_party_host: string] {
    $"($sender_party_host) ($WEBAPP_SHARE_SENDER_HUB_HOST)"
}

export def webapp-share-stack-env-lines [] {
    [
        $"SENDER_HUB_HOST=($WEBAPP_SHARE_SENDER_HUB_HOST)"
        $"SENDER_HUB_CRYPT_KEY=($WEBAPP_SHARE_HUB_CRYPT_KEY)"
        $"SENDER_HUB_API_KEY=($WEBAPP_SHARE_HUB_API_KEY)"
        $"SENDER_HUB_OCM_API_KEY=($WEBAPP_SHARE_HUB_OCM_API_KEY)"
    ]
}

export def webapp-share-runner-depends-on-lines [] {
    [
        "      sender-hub:"
        "        condition: service_healthy"
    ]
}

export def apply-webapp-share-compose-overlays [
    root: string,
    sender_platform: string,
    compose_d: string,
    artifacts_base: string,
] {
    patch-webapp-share-sender-yml $compose_d
    copy-platform-cookbook $root $sender_platform "webapp-hub" $compose_d
    mkdir ($artifacts_base | path join "oauth-handoff")
}

export def webapp-share-base-overlay-fnames [base_overlay_fnames: list<string>, flow_id: string] {
    if (is-webapp-share-flow $flow_id) {
        $base_overlay_fnames | append $WEBAPP_SHARE_HUB_OVERLAY_FNAME
    } else {
        $base_overlay_fnames
    }
}
