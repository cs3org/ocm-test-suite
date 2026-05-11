# Site publish configuration loading and validation.
# Reads config/site.nuon and exposes typed resolver helpers that honor
# existing env vars as higher-priority overrides.

use ../domain/core/ocmts-root.nu [get-ocmts-root]
use ../ci/zstd.nu [default_zstd_archive_policy]

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
    "deploy_base_path"
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

# Validate the archive_zstd sub-record if present.
# level must be 1-19; threads >= 0; checksum must be bool.
def validate-zstd-policy [policy: any] {
    if $policy == null { return }
    let level = ($policy.level? | default null)
    let threads = ($policy.threads? | default null)
    let checksum = ($policy.checksum? | default null)
    if $level == null {
        error make {msg: "config/site.nuon archive_zstd: missing required key: level"}
    }
    if $threads == null {
        error make {msg: "config/site.nuon archive_zstd: missing required key: threads"}
    }
    if $checksum == null {
        error make {msg: "config/site.nuon archive_zstd: missing required key: checksum"}
    }
    if ($checksum | describe) != "bool" {
        error make {msg: $"config/site.nuon archive_zstd: checksum must be bool, got ($checksum | describe)"}
    }
    if $level < 1 or $level > 19 {
        error make {msg: $"config/site.nuon archive_zstd: level must be 1-19, got ($level)"}
    }
    if $threads < 0 {
        error make {msg: $"config/site.nuon archive_zstd: threads must be >= 0, got ($threads)"}
    }
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
    if ($cfg.deploy_base_path | is-empty) {
        error make {msg: "config/site.nuon: deploy_base_path must not be empty"}
    }
    validate-zstd-policy ($cfg.archive_zstd? | default null)
    $cfg
}

# Resolve the effective zstd archive policy.
# Returns the archive_zstd record from config/site.nuon when present,
# or default_zstd_archive_policy as a fallback when config is unavailable.
export def resolve-zstd-archive-policy []: nothing -> record {
    let cfg = (try { load-site-cfg } catch { null })
    let policy = if $cfg != null {
        ($cfg.archive_zstd? | default null)
    } else {
        null
    }
    if $policy != null { $policy } else { $default_zstd_archive_policy }
}

# Resolve the effective site git ref.
# Priority: explicit arg > OCMTS_SITE_REF env > config/site.nuon ref.
# Config is the final authority; the ref field there sets the branch used for
# source site clones when no override is supplied via arg or env.
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
    "master"
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

# Resolve the effective deploy base path (passed as ASTRO_BASE to the site build).
# This is the URL base path under which the site is hosted on the Pages host repo,
# e.g. "/ocm-test-suite/" for cs3org/ocm-test-suite GitHub Pages.
# Priority: explicit arg > OCMTS_DEPLOY_BASE env > config/site.nuon deploy_base_path.
export def resolve-effective-deploy-base-path [arg_base: string] {
    if not ($arg_base | is-empty) {
        return $arg_base
    }
    let env_base = ($env.OCMTS_DEPLOY_BASE? | default "")
    if not ($env_base | is-empty) {
        return $env_base
    }
    let cfg = (try { load-site-cfg } catch { null })
    if ($cfg != null) and (not ($cfg.deploy_base_path? | default "" | is-empty)) {
        return $cfg.deploy_base_path
    }
    "/"
}

# Resolve the effective deploy site URL (passed as ASTRO_SITE to the site build).
# This is the full canonical URL of the Pages host, e.g.
# "https://cs3org.github.io/ocm-test-suite/". ASTRO_SITE is optional in the
# Astro config; returns empty string when not configured.
# Priority: OCMTS_DEPLOY_SITE_URL env > config/site.nuon deploy_site_url.
export def resolve-effective-deploy-site-url [] {
    let env_url = ($env.OCMTS_DEPLOY_SITE_URL? | default "")
    if not ($env_url | is-empty) {
        return $env_url
    }
    let cfg = (try { load-site-cfg } catch { null })
    if $cfg != null {
        return ($cfg.deploy_site_url? | default "")
    }
    ""
}
