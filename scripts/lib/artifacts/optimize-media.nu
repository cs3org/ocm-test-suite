# Per-cell optimized media production.
# Discovers raw PNG screenshots and MP4 videos in a cell artifact directory,
# converts each to optimized formats via the ffmpeg optimizer image, and emits
# meta/optimized-media-cell.v1.json. Every cell emits a manifest, even with
# no source media (status: no-source-media).

# Internal: derive (optimized_path, codec_args, role, format, mime) for each
# output variant of a source file. Returns two entries per source: primary then
# fallback. codec_args are internal and not written to the manifest.
def derive-conversions [src_rel: string, kind: string] {
    let p = ($src_rel | path parse)
    let stem = $p.stem
    let parent = $p.parent
    let stem_path = if ($parent | is-empty) { $stem } else { ($parent | path join $stem) }

    if $kind == "screenshot" {
        [
            {
                optimized_path: $"($stem_path).avif"
                role: "primary"
                format: "avif"
                mime: "image/avif"
                codec_args: ["-c:v" "libaom-av1" "-still-picture" "1"]
            }
            {
                optimized_path: $"($stem_path).webp"
                role: "fallback"
                format: "webp"
                mime: "image/webp"
                codec_args: ["-c:v" "libwebp"]
            }
        ]
    } else if $kind == "video" {
        # Cypress recordings have no audio. -an is correct for cypress media only;
        # do not reuse this helper for general video without first probing for an
        # audio stream and adding -c:a libopus.
        [
            {
                optimized_path: $"($stem_path).av1.webm"
                role: "primary"
                format: "av1-webm"
                mime: "video/webm"
                codecs: "av01"
                codec_args: ["-c:v" "libaom-av1" "-an"]
            }
            {
                optimized_path: $"($stem_path).vp9.webm"
                role: "fallback"
                format: "vp9-webm"
                mime: "video/webm"
                codecs: "vp9"
                codec_args: ["-c:v" "libvpx-vp9" "-an"]
            }
        ]
    } else {
        error make {msg: $"Unknown media kind: ($kind). Expected screenshot or video."}
    }
}

# Discover publishable raw media in a cell artifact root directory.
# The root is the downloaded artifact directory that contains artifacts/<flow>/<pair>/<exec-id>/.
# Returns list of {rel, kind} where kind is "screenshot" or "video".
# rel is relative to raw_dir, e.g. artifacts/flow/pair/exec/cypress/screenshots/foo.png.
export def discover-raw-media [raw_dir: string] {
    let base = ($raw_dir | path expand)
    let prefix = $"($base)/"

    let ss_abs = (try {
        glob ($base | path join "artifacts/**/cypress/screenshots/**/*.png")
    } catch { [] })
    let vid_abs = (try {
        glob ($base | path join "artifacts/**/cypress/videos/*.mp4")
    } catch { [] })

    let ss_items = ($ss_abs | each {|p|
        {rel: ($p | str replace $prefix ""), kind: "screenshot"}
    })
    let vid_items = ($vid_abs | each {|p|
        {rel: ($p | str replace $prefix ""), kind: "video"}
    })

    ($ss_items | append $vid_items)
}

# Build manifest item records for one source file.
# Returns two records: primary then fallback.
# Manifest items contain source_path, optimized_path, kind, status, role,
# format, mime, and codecs (video only). codec_args are stripped from output.
export def planned-output-items [src_rel: string, kind: string] {
    let convs = (derive-conversions $src_rel $kind)
    $convs | each {|c|
        let base = {
            source_path: $src_rel
            optimized_path: $c.optimized_path
            kind: $kind
            status: "optimized"
            role: $c.role
            format: $c.format
            mime: $c.mime
        }
        if ($c.codecs? != null) {
            $base | insert codecs $c.codecs
        } else {
            $base
        }
    }
}

# Run one ffmpeg conversion via docker.
# raw_dir and out_dir must be absolute paths on the host.
# Returns {ok, exit_code, stderr}.
export def run-ffmpeg-convert [
    image: string,
    raw_dir: string,
    out_dir: string,
    src_rel: string,
    dst_rel: string,
    codec_args: list<string>,
] {
    let raw_abs = ($raw_dir | path expand)
    let out_abs = ($out_dir | path expand)
    let out_path = ($out_abs | path join $dst_rel)
    mkdir ($out_path | path dirname)

    let base_args = [
        "run" "--rm"
        "-v" $"($raw_abs):/input:ro"
        "-v" $"($out_abs):/output"
        $image
        "-y" "-loglevel" "error"
        "-i" $"/input/($src_rel)"
    ]
    let out_arg = [$"/output/($dst_rel)"]
    let docker_args = ($base_args | append $codec_args | append $out_arg)

    let result = (try {
        ^docker ...$docker_args | complete
    } catch {|e|
        {exit_code: 1, stdout: "", stderr: $e.msg}
    })

    {ok: ($result.exit_code == 0), exit_code: $result.exit_code, stderr: ($result.stderr | str trim)}
}

# Write meta/optimized-media-cell.v1.json into out_dir.
def emit-manifest [out_dir: string, items: list, status: string, optimizer_image: string] {
    let meta_dir = ($out_dir | path join "meta")
    mkdir $meta_dir
    let generated_at = (date now | date to-timezone "UTC" | format date "%Y-%m-%dT%H:%M:%SZ")
    {
        schema_version: 1,
        generated_at: $generated_at,
        status: $status,
        optimizer_image: $optimizer_image,
        items: $items,
    }
    | to json --indent 2
    | save --force ($meta_dir | path join "optimized-media-cell.v1.json")
}

# Optimize one raw cell artifact directory.
# Discovers PNG screenshots and MP4 videos, converts each to AVIF/WebP or
# AV1 WebM/VP9 WebM, and emits meta/optimized-media-cell.v1.json.
# Returns the manifest record.
export def optimize-cell-media [
    raw_dir: string,   # path to the raw cell artifact directory
    out_dir: string,   # path to write optimized outputs into
    image: string,     # optimizer docker image ref
] {
    let raw_abs = ($raw_dir | path expand)
    let out_abs = ($out_dir | path expand)
    mkdir $out_abs

    let sources = (discover-raw-media $raw_abs)

    if ($sources | is-empty) {
        emit-manifest $out_abs [] "no-source-media" $image
        return {
            schema_version: 1,
            status: "no-source-media",
            optimizer_image: $image,
            items: [],
        }
    }

    # Plan all output items across all sources.
    let planned = ($sources | each {|src|
        let convs = (derive-conversions $src.rel $src.kind)
        $convs | each {|c|
            let base = {
                source_path: $src.rel
                optimized_path: $c.optimized_path
                kind: $src.kind
                role: $c.role
                format: $c.format
                mime: $c.mime
                codec_args: $c.codec_args
            }
            if ($c.codecs? != null) {
                $base | insert codecs $c.codecs
            } else {
                $base
            }
        }
    } | flatten)

    mut item_records = []
    for item in $planned {
        let run_result = (run-ffmpeg-convert
            $image $raw_abs $out_abs
            $item.source_path $item.optimized_path $item.codec_args)

        let item_status = if $run_result.ok { "optimized" } else { "failed" }
        if not $run_result.ok {
            print $"WARNING: ffmpeg failed for ($item.source_path) -> ($item.optimized_path): ($run_result.stderr)"
        }

        let item_base = {
            source_path: $item.source_path
            optimized_path: $item.optimized_path
            kind: $item.kind
            status: $item_status
            role: $item.role
            format: $item.format
            mime: $item.mime
        }
        let item_rec = if ($item.codecs? != null) {
            $item_base | insert codecs $item.codecs
        } else {
            $item_base
        }
        $item_records = ($item_records | append $item_rec)
    }

    let all_optimized = ($item_records | all {|r| $r.status == "optimized"})
    let overall_status = if $all_optimized { "optimized" } else { "failed" }

    emit-manifest $out_abs $item_records $overall_status $image

    {
        schema_version: 1,
        status: $overall_status,
        optimizer_image: $image,
        items: $item_records,
    }
}
