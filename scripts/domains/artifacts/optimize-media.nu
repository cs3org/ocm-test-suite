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
    --out-dir: string,       # path to write optimized outputs (required)
    --image: string = "",    # override the optimizer image; defaults to config value
] {
    if ($raw_dir | is-empty) {
        error make {msg: "Missing required flag --raw-dir"}
    }
    if ($out_dir | is-empty) {
        error make {msg: "Missing required flag --out-dir"}
    }

    let img = if ($image | is-empty) {
        resolve-media-optimizer-image
    } else {
        $image
    }

    print $"Optimizing media:"
    print $"  raw-dir:  ($raw_dir)"
    print $"  out-dir:  ($out_dir)"
    print $"  image:    ($img)"

    let result = (optimize-cell-media $raw_dir $out_dir $img)

    print $"  status:   ($result.status)"
    print $"  items:    ($result.items | length)"

    let failed = ($result.items | where status == "failed")
    if ($failed | is-not-empty) {
        let fail_count = ($failed | length)
        let paths = ($failed | each {|r| $r.source_path} | str join ", ")
        print $"  WARNING: ($fail_count) failed conversions: ($paths)"
    }
}
