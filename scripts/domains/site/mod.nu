# Site domain: clone, ingest, build, publish, and preview the ocm-web-site.

use ../../lib/site/clone.nu [resolve-site-dir, clone-or-refresh-site]
use ../../lib/site/config.nu [resolve-effective-site-ref]
use ../../lib/site/ingest.nu [ingest-site]
use ../../lib/site/build.nu [run-site-build]
use ../../lib/domain/core/ocmts-root.nu [get-ocmts-root]
use ../../lib/matrix/rules-gen.nu [load-matrix-rules]
use ../../lib/site/publish.nu [run-site-publish]
use ../../lib/site/preview.nu [run-site-preview]

def main [] {
    print "Usage: nu scripts/ocmts.nu site <verb> [flags]"
    print ""
    print "Verbs:"
    print "  clone    Clone or refresh the ocm-web-site repo"
    print "  ingest   Generate site JSON inputs and copy artifacts"
    print "  build    Build the Astro site"
    print "  publish  clone + ingest + build (CI entrypoint)"
    print "  preview  Start a local preview server for a built site"
    print ""
    print "Environment variables:"
    print "  OCMTS_SITE_REPO_SLUG  default: MahdiBaghbani/ocm-web-site"
    print "  OCMTS_SITE_REPO_URL   optional full URL override"
    print "  OCMTS_SITE_REF        git ref to checkout (overrides config/site.nuon ref)"
    print "  OCM_WEB_SITE_DIR      local site dir override for all verbs; skips clone"
}

# Clone or refresh the ocm-web-site repo.
def "main clone" [
    --site-dir: string = "",  # Destination dir (default: OCM_WEB_SITE_DIR env, then ../ocm-web-site)
    --ref: string = "",       # Git ref; falls back to OCMTS_SITE_REF env, then config/site.nuon ref
] {
    let effective_ref = (resolve-effective-site-ref $ref)
    let site = (resolve-site-dir $site_dir)
    clone-or-refresh-site $site $effective_ref
    print $"Site dir: ($site)"
}

# Generate suite-manifest.v1.json, matrix-rules.v1.json, and copy allowlisted
# artifacts into the site public/ directory.
def "main ingest" [
    --site-dir: string = "",       # Site repo dir (default: OCM_WEB_SITE_DIR env, then ../ocm-web-site)
    --artifacts-root: string = "", # OCMTS artifacts root (default: <ocmts-root>/artifacts)
    --public-dir: string = "",     # Output dir (default: <site-dir>/public)
    --suite-id: string = "",       # Ingest runs from this suite_id only
    --latest-suite,                # Ingest runs from the latest suite (LATEST_SUITE_ID)
] {
    if (not ($suite_id | is-empty)) and $latest_suite {
        error make {msg: "--suite-id and --latest-suite are mutually exclusive"}
    }
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
    let rules = (load-matrix-rules $root)
    if $latest_suite {
        ingest-site $art_root $rules $root $pub_dir --latest-suite
    } else if not ($suite_id | is-empty) {
        ingest-site $art_root $rules $root $pub_dir --suite-id $suite_id
    } else {
        ingest-site $art_root $rules $root $pub_dir
    }
}

# Build the Astro site (bun preferred, npm fallback). Does not start a dev server.
def "main build" [
    --site-dir: string = "",  # Site repo dir (default: OCM_WEB_SITE_DIR env, then ../ocm-web-site)
] {
    let site = (resolve-site-dir $site_dir)
    if not ($site | path exists) {
        error make {msg: $"Site dir not found: ($site). Run `site clone` first."}
    }
    run-site-build $site
    print "Build complete."
}

# Start a local preview server for a built site directory.
# Blocks until Ctrl+C. Requires a completed `site build` first.
def "main preview" [
    --site-dir: string = "",    # Site repo dir (default: OCM_WEB_SITE_DIR env, then ../ocm-web-site)
    --host: string = "localhost", # Host address to bind
    --port: int = 4321,           # Port to listen on
] {
    let eff_site_dir = (resolve-site-dir $site_dir)
    run-site-preview $eff_site_dir $host $port
}

# Orchestrate clone (optional), ingest, optional media projection, and build.
def "main publish" [
    --site-dir: string = "",            # Site repo dir (default: OCM_WEB_SITE_DIR env, then ../ocm-web-site; skips clone when set)
    --artifacts-root: string = "",      # OCMTS artifacts root (default: <ocmts-root>/artifacts)
    --skip-clone,                       # Skip git clone/refresh
    --ref: string = "",                 # Git ref; falls back to OCMTS_SITE_REF env, then config/site.nuon ref
    --suite-id: string = "",            # Ingest runs from this suite_id only
    --latest-suite,                     # Ingest runs from the latest suite (LATEST_SUITE_ID)
    --optimized-media-dir: string = "", # Optimized media aggregate dir (skip projection if empty)
] {
    if (not ($suite_id | is-empty)) and $latest_suite {
        error make {msg: "--suite-id and --latest-suite are mutually exclusive"}
    }
    (run-site-publish
        $site_dir $artifacts_root $skip_clone $ref $suite_id $latest_suite
        $optimized_media_dir)
}
