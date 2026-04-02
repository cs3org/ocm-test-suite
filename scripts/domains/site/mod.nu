# Site domain: clone, ingest, build, and publish the ocm-web-site.

use ../../lib/site-clone.nu [resolve-site-dir, clone-or-refresh-site]
use ../../lib/site-ingest.nu [ingest-site, run-site-build]
use ../../lib/domain/core/ocmts-root.nu [get-ocmts-root]

def main [] {
    print "Usage: nu scripts/ocmts.nu site <verb> [flags]"
    print ""
    print "Verbs:"
    print "  clone    Clone or refresh the ocm-web-site repo"
    print "  ingest   Generate site JSON inputs and copy artifacts"
    print "  build    Build the Astro site"
    print "  publish  clone + ingest + build (CI entrypoint)"
    print ""
    print "Environment variables:"
    print "  OCMTS_SITE_REPO_SLUG  default: MahdiBaghbani/ocm-web-site"
    print "  OCMTS_SITE_REPO_URL   optional full URL override"
    print "  OCMTS_SITE_REF        git ref to checkout (default: main)"
}

# Clone or refresh the ocm-web-site repo.
def "main clone" [
    --site-dir: string = "",  # Destination dir (default: ../ocm-web-site)
    --ref: string = "",       # Git ref; falls back to OCMTS_SITE_REF, then main
] {
    let effective_ref = if not ($ref | is-empty) {
        $ref
    } else {
        ($env.OCMTS_SITE_REF? | default "main")
    }
    let site = (resolve-site-dir $site_dir)
    clone-or-refresh-site $site $effective_ref
    print $"Site dir: ($site)"
}

# Generate suite-manifest.v1.json, matrix-rules.v1.json, and copy allowlisted
# artifacts into the site public/ directory.
def "main ingest" [
    --site-dir: string = "",       # Site repo dir (default: ../ocm-web-site)
    --artifacts-root: string = "", # OTS artifacts root (default: <ots-root>/artifacts)
    --public-dir: string = "",     # Output dir (default: <site-dir>/public)
] {
    let root = get-ocmts-root
    let site = (resolve-site-dir $site_dir)
    let art_root = if not ($artifacts_root | is-empty) {
        $artifacts_root
    } else {
        $root | path join "artifacts"
    }
    let pub_dir = if not ($public_dir | is-empty) {
        $public_dir
    } else {
        $site | path join "public"
    }
    let rules_path = ($root | path join "config/matrix-rules.nuon")
    if not ($rules_path | path exists) {
        error make {msg: $"Matrix rules not found: ($rules_path)"}
    }
    ingest-site $art_root $rules_path $pub_dir
}

# Build the Astro site (bun preferred, npm fallback). Does not start a dev server.
def "main build" [
    --site-dir: string = "",  # Site repo dir (default: ../ocm-web-site)
] {
    let site = (resolve-site-dir $site_dir)
    if not ($site | path exists) {
        error make {msg: $"Site dir not found: ($site). Run `site clone` first."}
    }
    run-site-build $site
    print "Build complete."
}

# Orchestrate clone (optional), ingest, and build in one step.
def "main publish" [
    --site-dir: string = "",       # Site repo dir (default: ../ocm-web-site)
    --artifacts-root: string = "", # OTS artifacts root (default: <ots-root>/artifacts)
    --skip-clone,                  # Skip git clone/refresh
    --ref: string = "",            # Git ref; falls back to OCMTS_SITE_REF, then main
] {
    let root = get-ocmts-root
    let site = (resolve-site-dir $site_dir)
    let art_root = if not ($artifacts_root | is-empty) {
        $artifacts_root
    } else {
        $root | path join "artifacts"
    }
    let rules_path = ($root | path join "config/matrix-rules.nuon")
    let pub_dir = ($site | path join "public")

    if not $skip_clone {
        let effective_ref = if not ($ref | is-empty) {
            $ref
        } else {
            ($env.OCMTS_SITE_REF? | default "main")
        }
        clone-or-refresh-site $site $effective_ref
    }

    if not ($rules_path | path exists) {
        error make {msg: $"Matrix rules not found: ($rules_path)"}
    }
    ingest-site $art_root $rules_path $pub_dir

    if not ($site | path exists) {
        error make {msg: $"Site dir not found: ($site). Cannot build."}
    }
    run-site-build $site
    print "Publish complete."
}
