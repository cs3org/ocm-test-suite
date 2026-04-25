# Git clone and refresh helpers for the site domain.

use ../domain/core/ocmts-root.nu [get-ocmts-root]
use ./config.nu [resolve-effective-site-repo-url]

# Resolve the site repo URL from env or config/site.nuon.
# Priority: OCMTS_SITE_REPO_URL env > config repo_url_override >
# OCMTS_SITE_REPO_SLUG env > config repo_slug.
export def resolve-site-repo-url [] {
    resolve-effective-site-repo-url
}

# Resolve the local site clone directory.
# Priority: explicit override arg > OCM_WEB_SITE_DIR env > default sibling path.
# Absolute overrides pass through unchanged; relative overrides resolve
# from the OCM Test Suite repo root, not from the caller's shell cwd.
export def resolve-site-dir [override: string] {
    let root = get-ocmts-root
    if not ($override | is-empty) {
        if ($override | str starts-with "/") {
            $override
        } else {
            $root | path join $override
        }
    } else {
        let env_dir = ($env.OCM_WEB_SITE_DIR? | default "")
        if not ($env_dir | is-empty) {
            $env_dir
        } else {
            ($root | path dirname) | path join "ocm-web-site"
        }
    }
}

# Returns true when the site dir was explicitly provided (arg or OCM_WEB_SITE_DIR env).
# Callers use this to decide whether to skip git clone/refresh for a local source.
export def site-dir-is-local [override: string] {
    let env_dir = ($env.OCM_WEB_SITE_DIR? | default "")
    (not ($override | is-empty)) or (not ($env_dir | is-empty))
}

# Clone fresh, or fetch + checkout an existing clone.
# Uses OCMTS_SITE_REF env or `ref` arg for the branch/tag/SHA.
export def clone-or-refresh-site [site_dir: string, ref: string] {
    let git_dir = ($site_dir | path join ".git")
    if ($git_dir | path exists) {
        print $"Site repo exists at ($site_dir), fetching..."
        let r = (^git -C $site_dir fetch origin | complete)
        if $r.exit_code != 0 {
            error make {msg: $"git fetch failed in ($site_dir): ($r.stderr | str trim)"}
        }
        let r2 = (^git -C $site_dir checkout $ref | complete)
        if $r2.exit_code != 0 {
            error make {msg: $"git checkout ($ref) failed: ($r2.stderr | str trim)"}
        }
        print $"Site repo refreshed on ref ($ref)"
    } else {
        let url = resolve-site-repo-url
        print $"Cloning ($url) -> ($site_dir) at ref ($ref)..."
        let r = (^git clone --branch $ref $url $site_dir | complete)
        if $r.exit_code != 0 {
            error make {msg: $"git clone failed: ($r.stderr | str trim)"}
        }
        print $"Site repo cloned to ($site_dir)"
    }
}
