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
    "site"
]

# Profiles valid for the Pages build.
const KNOWN_SITE_PROFILES = ["", "observatory-root"]
const KNOWN_SITE_PAGE_KEYS = ["home", "observatory", "validator", "statistics"]

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

# Validate the required site sub-record.
def validate-site-subrecord [site: any] {
    if $site == null {
        error make {msg: "config/site.nuon missing required key: site"}
    }
    if not (($site | describe) | str starts-with "record") {
        error make {msg: $"config/site.nuon site must be a record, got ($site | describe)"}
    }
    for key in [profile primary community_url logo_href] {
        let val = ($site | get --optional $key)
        if $val == null {
            error make {msg: $"config/site.nuon site: missing required key: ($key)"}
        }
        if ($val | describe) != "string" {
            error make {msg: $"config/site.nuon site.($key) must be string, got ($val | describe)"}
        }
    }
    let profile = $site.profile
    if $profile not-in $KNOWN_SITE_PROFILES {
        error make {msg: $"config/site.nuon site.profile must be one of ($KNOWN_SITE_PROFILES | str join ', '), got ($profile)"}
    }
    let primary = $site.primary
    if $primary not-in $KNOWN_SITE_PAGE_KEYS {
        error make {msg: $"config/site.nuon site.primary must be one of ($KNOWN_SITE_PAGE_KEYS | str join ', '), got ($primary)"}
    }
    if ($site.community_url | is-empty) {
        error make {msg: "config/site.nuon site.community_url must not be empty"}
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
    validate-site-subrecord ($cfg.site? | default null)
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

# Resolve the effective site profile (passed as SITE_PROFILE to the site build).
# Priority: explicit arg > OCMTS_SITE_PROFILE env > config/site.nuon site.profile.
export def resolve-effective-site-profile [arg: string] {
    if not ($arg | is-empty) {
        return $arg
    }
    let env_profile = ($env.OCMTS_SITE_PROFILE? | default "")
    if not ($env_profile | is-empty) {
        return $env_profile
    }
    let cfg = (try { load-site-cfg } catch { null })
    if $cfg != null {
        let cfg_profile = ($cfg.site?.profile?)
        if $cfg_profile != null {
            return $cfg_profile
        }
    }
    ""
}

# Resolve the effective primary page key (passed as SITE_PRIMARY_PAGE).
# Priority: explicit arg > OCMTS_SITE_PRIMARY env > config/site.nuon site.primary.
export def resolve-effective-site-primary [arg: string] {
    if not ($arg | is-empty) {
        return $arg
    }
    let env_primary = ($env.OCMTS_SITE_PRIMARY? | default "")
    if not ($env_primary | is-empty) {
        return $env_primary
    }
    let cfg = (try { load-site-cfg } catch { null })
    if ($cfg != null) and (not ($cfg.site?.primary? | default "" | is-empty)) {
        return $cfg.site.primary
    }
    "observatory"
}

# Resolve the effective community URL (passed as SITE_COMMUNITY_URL).
# Priority: explicit arg > OCMTS_SITE_COMMUNITY_URL env > config/site.nuon site.community_url.
export def resolve-effective-community-url [arg: string] {
    if not ($arg | is-empty) {
        return $arg
    }
    let env_url = ($env.OCMTS_SITE_COMMUNITY_URL? | default "")
    if not ($env_url | is-empty) {
        return $env_url
    }
    let cfg = (try { load-site-cfg } catch { null })
    if ($cfg != null) and (not ($cfg.site?.community_url? | default "" | is-empty)) {
        return $cfg.site.community_url
    }
    ""
}

# Resolve the effective logo href (passed as SITE_LOGO_HREF).
# Empty config value falls through to the effective community URL.
# Priority: explicit arg > OCMTS_SITE_LOGO_HREF env > config/site.nuon site.logo_href
# > resolve-effective-community-url.
export def resolve-effective-logo-href [arg: string] {
    if not ($arg | is-empty) {
        return $arg
    }
    let env_href = ($env.OCMTS_SITE_LOGO_HREF? | default "")
    if not ($env_href | is-empty) {
        return $env_href
    }
    let cfg = (try { load-site-cfg } catch { null })
    if $cfg != null {
        let cfg_href = ($cfg.site?.logo_href? | default null)
        if ($cfg_href != null) and (not ($cfg_href | is-empty)) {
            return $cfg_href
        }
    }
    resolve-effective-community-url ""
}

# Derive Astro/SITE env values from a (possibly merged) config record.
# No disk reads or env lookups; used by CI workflow generation.
export def site-build-env-from-cfg [cfg: record] {
    let deploy_base = if not (($cfg.deploy_base_path? | default "") | is-empty) {
        $cfg.deploy_base_path
    } else {
        "/"
    }
    let community_url = ($cfg.site?.community_url? | default "")
    let logo_href_cfg = ($cfg.site?.logo_href? | default "")
    let logo_href = if not ($logo_href_cfg | is-empty) {
        $logo_href_cfg
    } else {
        $community_url
    }
    let site_primary = if not (($cfg.site?.primary? | default "") | is-empty) {
        $cfg.site.primary
    } else {
        "observatory"
    }
    {
        ASTRO_BASE: $deploy_base
        ASTRO_SITE: ($cfg.deploy_site_url? | default "")
        SITE_PROFILE: ($cfg.site?.profile? | default "")
        SITE_PRIMARY_PAGE: $site_primary
        SITE_COMMUNITY_URL: $community_url
        SITE_LOGO_HREF: $logo_href
    }
}

# Local-build SSOT: honor OCMTS_* env via existing resolvers.
export def resolve-effective-site-build-env [] {
    {
        ASTRO_BASE: (resolve-effective-deploy-base-path "")
        ASTRO_SITE: (resolve-effective-deploy-site-url)
        SITE_PROFILE: (resolve-effective-site-profile "")
        SITE_PRIMARY_PAGE: (resolve-effective-site-primary "")
        SITE_COMMUNITY_URL: (resolve-effective-community-url "")
        SITE_LOGO_HREF: (resolve-effective-logo-href "")
    }
}
