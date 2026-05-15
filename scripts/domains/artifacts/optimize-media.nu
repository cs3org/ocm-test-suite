# Optimize media for one raw cell artifact directory.
# Discovers PNG screenshots and MP4 videos, converts each to AVIF/WebP
# (screenshots) and AV1 WebM/VP9 WebM (videos), and emits
# meta/optimized-media-cell.v1.json. Emits a no-source-media manifest
# for cells with no publishable media. Resolves optimizer image from
# config/images.nuon unless --image is given.

use ../../lib/images/resolve.nu [resolve-media-optimizer-image]
use ../../lib/artifacts/optimize-media.nu [optimize-cell-media]

def main [
    --raw-dir: string,       # artifact root containing artifacts/<flow>/<pair>/<exec-id>/ (required)
    --output-dir: string,       # path to write optimized outputs (required)
    --image: string = "",    # override the optimizer image; defaults to config value
] {
    if ($raw_dir | is-empty) {
        error make {msg: "Missing required flag --raw-dir"}
    }
    if ($output_dir | is-empty) {
        error make {msg: "Missing required flag --output-dir"}
    }

    let artifacts_path = ($raw_dir | path join "artifacts")
    if not ($artifacts_path | path exists) {
        error make {msg: "optimize-media: --raw-dir must be a directory that contains artifacts/<flow>/<pair>/<exec-id>/. Pass repo root (.) or the artifact download root, not artifacts/ or a single cell dir."}
    }

    let img = if ($image | is-empty) {
        resolve-media-optimizer-image
    } else {
        $image
    }

    print $"Optimizing media:"
    print $"  raw-dir:  ($raw_dir)"
    print $"  out-dir:  ($output_dir)"
    print $"  image:    ($img)"

    let result = (optimize-cell-media $raw_dir $output_dir $img)

    print $"  status:   ($result.status)"
    print $"  items:    ($result.items | length)"

    let failed = ($result.items | where status == "failed")
    if ($failed | is-not-empty) {
        let fail_count = ($failed | length)
        let paths = ($failed | each {|r| $r.source_path} | str join ", ")
        print $"  FAILED: ($fail_count) failed conversions: ($paths)"
        error make {msg: $"optimize-media: ($fail_count) item(s) failed conversion"}
    }
}
