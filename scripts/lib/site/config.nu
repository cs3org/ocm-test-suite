# Site publish configuration loading and validation.
# Reads config/site.nuon and exposes typed resolver helpers that honor
# existing env vars as higher-priority overrides.

use ../domain/core/ocmts-root.nu [get-ocmts-root]

# Keys that must be present and non-null in config/site.nuon.
const REQUIRED_SITE_CFG_KEYS = [
    "schema_version"
    "repo_slug"
    "ref"
    "publish_branch_gate"
    "site_build_output_path"
    "raw_aggregate_artifact_name"
    "optimized_artifact_pattern"
    "optimized_aggregate_artifact_name"
    "rebuild_source_workflow"
]

# Load config/site.nuon from the OCMTS repo root.
export def load-site-cfg [] {
    let root = get-ocmts-root
    let cfg_path = ($root | path join "config/site.nuon")
    if not ($cfg_path | path exists) {
        error make {msg: $"config/site.nuon not found at ($cfg_path)"}
    }
    open $cfg_path
}

# Validate that a site config record has all required keys and non-empty
# required string fields. Returns the record unchanged on success.
export def validate-site-cfg [cfg: record] {
    for key in $REQUIRED_SITE_CFG_KEYS {
        let val = ($cfg | get --optional $key)
        if $val == null {
            error make {msg: $"config/site.nuon missing required key: ($key)"}
        }
    }
    if ($cfg.repo_slug | is-empty) {
        error make {msg: "config/site.nuon: repo_slug must not be empty"}
    }
    if ($cfg.ref | is-empty) {
        error make {msg: "config/site.nuon: ref must not be empty"}
    }
    if ($cfg.publish_branch_gate | is-empty) {
        error make {msg: "config/site.nuon: publish_branch_gate must not be empty"}
    }
    if ($cfg.site_build_output_path | is-empty) {
        error make {msg: "config/site.nuon: site_build_output_path must not be empty"}
    }
    $cfg
}

# Resolve the effective site git ref.
# Priority: explicit arg > OCMTS_SITE_REF env > config/site.nuon ref > "main".
export def resolve-effective-site-ref [arg_ref: string] {
    if not ($arg_ref | is-empty) {
        return $arg_ref
    }
    let env_ref = ($env.OCMTS_SITE_REF? | default "")
    if not ($env_ref | is-empty) {
        return $env_ref
    }
    let cfg = (try { load-site-cfg } catch { null })
    if ($cfg != null) and (not ($cfg.ref? | default "" | is-empty)) {
        return $cfg.ref
    }
    "main"
}

# Resolve the effective site repo URL.
# Priority: OCMTS_SITE_REPO_URL env > config repo_url_override >
# OCMTS_SITE_REPO_SLUG env > config repo_slug > hardcoded fallback.
export def resolve-effective-site-repo-url [] {
    let url_env = ($env.OCMTS_SITE_REPO_URL? | default "")
    if not ($url_env | is-empty) {
        return $url_env
    }
    let cfg = (try { load-site-cfg } catch { null })
    if $cfg != null {
        let cfg_url = ($cfg.repo_url_override? | default "")
        if not ($cfg_url | is-empty) {
            return $cfg_url
        }
        let slug_env = ($env.OCMTS_SITE_REPO_SLUG? | default "")
        let slug = if not ($slug_env | is-empty) { $slug_env } else { $cfg.repo_slug }
        return $"https://github.com/($slug).git"
    }
    let slug = ($env.OCMTS_SITE_REPO_SLUG? | default "MahdiBaghbani/ocm-web-site")
    $"https://github.com/($slug).git"
}
