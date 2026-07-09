# Canonical list of valid public flow identifiers.
# All other modules that need this list import from here.
export const PUBLIC_FLOW_IDS = ["login" "share-with" "contact-token" "contact-wayf" "webapp-share"]

export const WEBAPP_SHARE_FLOW_ID = "webapp-share"

export def is-webapp-share-flow [flow_id: string]: nothing -> bool {
    $flow_id == $WEBAPP_SHARE_FLOW_ID
}
