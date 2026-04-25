# Optimized media test fixtures

These fixtures back the integration tests under
`scripts/tests/integration/`. They capture the smallest realistic input shapes
for the optimized-media lane so tests can exercise full chains
(optimize -> aggregate -> public projection) without running the suite.

## Layout

```text
optimized-media/
  raw-input/
    artifacts/login/nextcloud-v34/exec-fixture/
      cypress/screenshots/sample.png   real Cypress screenshot, 1000x633 RGBA, ~44 KB
      cypress/videos/sample.mp4        real Cypress recording (5s clip), 1280x632 H.264, ~32 KB
  pre-optimized/
    artifacts/login/nextcloud-v34/exec-fixture/
      cypress/screenshots/sample.avif  8-byte placeholder
      cypress/screenshots/sample.webp  8-byte placeholder
      cypress/videos/sample.av1.webm   8-byte placeholder
      cypress/videos/sample.vp9.webm   8-byte placeholder
    meta/optimized-media-cell.v1.json  matches the four placeholders
  pre-optimized-no-media/
    meta/optimized-media-cell.v1.json  status=no-source-media, items=[]
  raw-public-manifest.json             trimmed suite-manifest.v1.json shape
```

## Why placeholders for pre-optimized

The orchestration tests (`scripts/tests/integration/optimized-media-pipeline.nu`)
exercise `aggregate-optimized-media-cells` and `apply-media-projection`. Neither
function parses media file headers; they only check existence, copy bytes, and
validate paths. 8-byte marker content is safe and keeps the fixture tree small.

If you want byte-identical comparison with real optimizer output, regenerate the
files via the manual real-ffmpeg test
(`scripts/tests/integration/manual/optimized-media-real-ffmpeg.nu`) and copy its
output into this directory. Update this README if you do.

## Why real bytes for raw-input

The manual real-ffmpeg test (`scripts/tests/integration/manual/`) feeds these
files to the configured optimizer container and asserts the conversion produced
real AVIF, WebP, AV1 WebM, and VP9 WebM outputs. Placeholders would not decode.

These bytes were lifted from a real Cypress run (the share-with flow)
rather than synthesized via lavfi, so the optimizer sees realistic content
(actual UI text rendering for the screenshot, real H.264 frames for the
video). This catches issues that toy 2x2 white frames would mask.

## Regeneration recipe

Both binaries come from a real Cypress run on disk under
`artifacts/share-with/.../cypress/`. Pick any small screenshot and a short
section of any video and copy them in, renaming to `sample.png` and
`sample.mp4`. The exact source used today:

```text
# PNG (real Cypress screenshot, 1000x633 RGBA)
SRC=artifacts/share-with/nextcloud-v32-nextcloud-v32/<exec-id>/cypress/screenshots/index.cy.ts/share-with__nextcloud-v32__nextcloud-v32--004--receiver--share-visible.png
DST=scripts/tests/fixtures/optimized-media/raw-input/artifacts/login/nextcloud-v34/exec-fixture/cypress/screenshots/sample.png
cp "$SRC" "$DST"

# MP4 (5-second clip, stream-copied so frames are not re-encoded)
SRC_MP4=artifacts/share-with/nextcloud-v32-nextcloud-v32/<exec-id>/cypress/videos/share-with__nextcloud-v32__nextcloud-v32--run.mp4
DST_DIR=scripts/tests/fixtures/optimized-media/raw-input/artifacts/login/nextcloud-v34/exec-fixture/cypress/videos
docker run --rm \
  -v "$(dirname $SRC_MP4):/in:ro" -v "$DST_DIR:/out" \
  linuxserver/ffmpeg:version-8.1-cli \
  -y -hide_banner -loglevel error \
  -ss 0 -t 5 -i "/in/$(basename $SRC_MP4)" \
  -c:v copy -an -movflags +faststart /out/sample.mp4
```

Replace `<exec-id>` with whatever timestamped run dir is current. Any other
small Cypress screenshot and any 5-second MP4 clip will work; the fixture
identity is the renamed path, not the source filename.

Avoid hand-rolled PNG byte sequences (e.g. printf with literal
`\x89PNG...` bytes); they look fine to image viewers but fail under libpng
with `inflate returned error -3` because they ship a precomputed but
invalid zlib IDAT stream.

The cell manifest JSON files are hand-crafted to match the placeholder paths
and the contract shape documented in
`docs/operations/optimized-media.md`.

## Path conventions

- `flow_id = login`, `pair = nextcloud-v34`, `execution_id = exec-fixture`
- run prefix used by projection: `artifacts/login/nextcloud-v34/exec-fixture`
- evidence rows use RELATIVE paths (`cypress/screenshots/sample.png`); the
  projection code prepends the run prefix when locating files in the optimized
  aggregate.

If you change the layout, update both this README and the integration tests
that import these paths.
