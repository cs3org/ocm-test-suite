# Probe the ffmpeg optimizer image for required encoding capabilities.
# Uses docker run to query the image without a conversion run.

# Probe the optimizer image via docker run.
# Returns a record:
#   image:          the image that was probed
#   available:      false when docker pull/run failed
#   ffmpeg_version: first non-empty line of -version output, or ""
#   encoders:       {libwebp, libaom_av1, libvpx_vp9} bool fields
#   muxers:         {avif, webp, webm} bool fields
#   ok:             true only when available and all required caps are present
export def probe-optimizer-image [image: string] {
    let ver_result = (try {
        ^docker run --rm $image -version | complete
    } catch {|e|
        {exit_code: 127, stdout: "", stderr: $e.msg}
    })

    if $ver_result.exit_code != 0 {
        return {
            image: $image,
            available: false,
            ffmpeg_version: "",
            encoders: {libwebp: false, libaom_av1: false, libvpx_vp9: false},
            muxers: {avif: false, webp: false, webm: false},
            ok: false,
        }
    }

    let ver_text = $"($ver_result.stdout)($ver_result.stderr)"
    let first_line = (
        $ver_text | lines
        | where {|l| not ($l | str trim | is-empty)}
        | first
        | default ""
    )

    let enc_result = (try {
        ^docker run --rm $image -encoders | complete
    } catch {
        {exit_code: 1, stdout: "", stderr: ""}
    })
    let enc_text = if $enc_result.exit_code == 0 {
        $"($enc_result.stdout)($enc_result.stderr)"
    } else { "" }

    let mux_result = (try {
        ^docker run --rm $image -muxers | complete
    } catch {
        {exit_code: 1, stdout: "", stderr: ""}
    })
    let mux_text = if $mux_result.exit_code == 0 {
        $"($mux_result.stdout)($mux_result.stderr)"
    } else { "" }

    let has_webp = ($enc_text | str contains "libwebp")
    let has_aom = ($enc_text | str contains "libaom-av1")
    let has_vp9 = ($enc_text | str contains "libvpx-vp9")
    let has_avif_mux = ($mux_text | str contains "avif")
    let has_webp_mux = ($mux_text | str contains "webp")
    let has_webm_mux = ($mux_text | str contains "webm")

    let required_enc = [$has_webp $has_aom $has_vp9]
    let required_mux = [$has_avif_mux $has_webp_mux $has_webm_mux]
    let all_ok = (
        ($required_enc | all {|x| $x})
        and ($required_mux | all {|x| $x})
    )

    {
        image: $image,
        available: true,
        ffmpeg_version: $first_line,
        encoders: {libwebp: $has_webp, libaom_av1: $has_aom, libvpx_vp9: $has_vp9},
        muxers: {avif: $has_avif_mux, webp: $has_webp_mux, webm: $has_webm_mux},
        ok: $all_ok,
    }
}
