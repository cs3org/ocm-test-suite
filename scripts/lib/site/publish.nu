# Shared site publish orchestration: optional clone, ingest, and build.
# Used by the site domain CLI and reusable for future test-suite publish flows.

use ./clone.nu [resolve-site-dir, clone-or-refresh-site, site-dir-is-local]
use ./config.nu [resolve-effective-site-ref]
use ./ingest.nu [ingest-site]
use ./build.nu [run-site-build]
use ./project-media.nu [apply-media-projection manifest-has-media-rows]
use ../domain/core/ocmts-root.nu [get-ocmts-root]
use ../matrix/rules-gen.nu [load-matrix-rules]

# Run the full site publish pipeline: optional clone, ingest, and build.
#
# site_dir:            site dir override ("" = OCM_WEB_SITE_DIR env, then ../ocm-web-site)
# artifacts_root:      artifacts root override ("" = <ocmts-root>/artifacts)
# skip_clone:          skip git clone/refresh step; also auto-skipped when
#                      site_dir or OCM_WEB_SITE_DIR signals a local source
# ref:                 git ref ("" = OCMTS_SITE_REF env or main)
# suite_id:            ingest from this suite only ("" = all suites)
# latest_suite:        ingest from the latest suite (LATEST_SUITE_ID)
# optimized_media_dir: optional optimized media aggregate dir. If provided,
#                      apply-media-projection rewrites the public manifest to
#                      reference web-optimized variants. If omitted, the
#                      publish keeps the raw media that ingest-site copied.
export def run-site-publish [
    site_dir: string,
    artifacts_root: string,
    skip_clone: bool,
    ref: string,
    suite_id: string,
    latest_suite: bool,
    optimized_media_dir: string = "",
] {
    let root = get-ocmts-root
    let site = (resolve-site-dir $site_dir)
    let art_root = if not ($artifacts_root | is-empty) {
        $artifacts_root
    } else {
        $root | path join "artifacts"
    }
    let pub_dir = ($site | path join "public")

    # Auto-skip clone when a local source was specified (explicit arg or env).
    let effective_skip_clone = $skip_clone or (site-dir-is-local $site_dir)
    if not $effective_skip_clone {
        let effective_ref = (resolve-effective-site-ref $ref)
        clone-or-refresh-site $site $effective_ref
    }

    let rules = (load-matrix-rules $root)
    if $latest_suite {
        ingest-site $art_root $rules $root $pub_dir --latest-suite
    } else if not ($suite_id | is-empty) {
        ingest-site $art_root $rules $root $pub_dir --suite-id $suite_id
    } else {
        ingest-site $art_root $rules $root $pub_dir
    }

    if ($optimized_media_dir | is-empty) and (manifest-has-media-rows $pub_dir) {
        print --stderr "Publishing with raw media; pass --optimized-media-dir to apply web-optimized projection."
    }
    if not ($optimized_media_dir | is-empty) {
        print --stderr $"Applying media projection from: ($optimized_media_dir)"
        apply-media-projection $pub_dir $optimized_media_dir
    }

    if not ($site | path exists) {
        error make {msg: $"Site dir not found: ($site). Cannot build."}
    }
    run-site-build $site
    print "Publish complete."
}
