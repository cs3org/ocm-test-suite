# Probe the optimizer image for required encoding and muxing capabilities.
# Resolves image from config/images.nuon unless --image is given.

use ../../lib/images/resolve.nu [resolve-media-optimizer-image]
use ../../lib/artifacts/optimizer-probe.nu [probe-optimizer-image]

def main [
    --image: string = "",   # override the optimizer image; defaults to config value
] {
    let img = if ($image | is-empty) {
        resolve-media-optimizer-image
    } else {
        $image
    }

    print $"Probing optimizer image: ($img)"
    let probe = (probe-optimizer-image $img)

    print $"  available:      ($probe.available)"
    print $"  ffmpeg_version: ($probe.ffmpeg_version)"
    print $"  encoders:"
    print $"    libwebp:      ($probe.encoders.libwebp)"
    print $"    libaom_av1:   ($probe.encoders.libaom_av1)"
    print $"    libvpx_vp9:   ($probe.encoders.libvpx_vp9)"
    print $"  muxers:"
    print $"    avif:         ($probe.muxers.avif)"
    print $"    webp:         ($probe.muxers.webp)"
    print $"    webm:         ($probe.muxers.webm)"
    print $"  ok:             ($probe.ok)"

    if not $probe.ok {
        if not $probe.available {
            error make {msg: $"Optimizer image not available: ($img)"}
        } else {
            let missing_enc = (
                $probe.encoders
                | items {|k v| if not $v { $k } else { null }}
                | where {|x| $x != null}
            )
            let missing_mux = (
                $probe.muxers
                | items {|k v| if not $v { $k } else { null }}
                | where {|x| $x != null}
            )
            let enc_str = ($missing_enc | str join ", ")
            let mux_str = ($missing_mux | str join ", ")
            error make {msg: $"Optimizer image missing capabilities. encoders=($enc_str) muxers=($mux_str)"}
        }
    }
}
