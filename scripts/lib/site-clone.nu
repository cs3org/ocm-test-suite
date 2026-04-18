# Git clone and refresh helpers for the site domain.

use ./domain/core/ocmts-root.nu [get-ocmts-root]

# Resolve the site repo URL from env or default slug.
# OCMTS_SITE_REPO_URL overrides; otherwise builds from OCMTS_SITE_REPO_SLUG.
export def resolve-site-repo-url [] {
    let url_override = ($env.OCMTS_SITE_REPO_URL? | default "")
    if not ($url_override | is-empty) {
        return $url_override
    }
    let slug = ($env.OCMTS_SITE_REPO_SLUG? | default "MahdiBaghbani/ocm-web-site")
    $"https://github.com/($slug).git"
}

# Resolve the local site clone directory.
# override wins; default is ../ocm-web-site relative to this repo root.
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
        ($root | path dirname) | path join "ocm-web-site"
    }
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
