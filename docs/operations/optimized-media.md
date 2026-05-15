# Optimized Media Lane

The OCM Test Suite publishes its public site with derived media (AVIF, WebP,
AV1 WebM, VP9 WebM) instead of the raw PNG and MP4 captured during tests.
The optimized-media lane runs in parallel with raw test execution; raw
artifacts and raw manifests are never rewritten. See
`docs/architecture/media-projection.md` for the design rationale.

## Two-lane architecture

```text
                                    optimized-media-cell-<key>
       +---------------+      +---------------------------+
       |  ci-run-cell  |----> |  optimize-media (per cell) |--+
       +-------+-------+      +---------------------------+  |
               |                                              |
               | cell-<key>                                   |
               v                                              v
       +---------------+        +-----------------------------+
       |  ci-matrix    |        |   ci-site (aggregate-media) |
       |  aggregate    |        |   + projection + build      |
       +-------+-------+        +-------------+---------------+
               |                              |
               | aggregate-summary            | optimized-media-summary
               v                              v
              ci-site site-build job (consumes both aggregates)
                              |
                              v
                      Pages deploy
```

Raw lane: `cell-*` per cell, merged into `aggregate-summary`. Untouched by
the optimized lane.

Optimized lane: `optimized-media-<artifact-name>` per cell (no extra `cell-`
prefix; the artifact name already starts with `cell-`). Merged into
`optimized-media-summary` by `ci-site.yml`.

Site lane: `ci-site.yml` downloads both aggregates, projects media rows in
the public manifest, copies derived media into the public artifact tree,
removes raw `.png` and `.mp4` from public, builds the Astro site, deploys
to GitHub Pages.

## Configuration

Site publish settings: `config/site.nuon`.

| Key | Purpose |
| --- | --- |
| `repo_slug` | Source site repo `<owner>/<name>` used for clone |
| `ref` | Default git ref for site checkout |
| `publish_branch_gate` | Branch on which optimized-media work runs |
| `site_build_output_path` | Output dir relative to site repo (`dist`) |
| `raw_aggregate_artifact_name` | Raw aggregate artifact name |
| `optimized_artifact_pattern` | Glob for per-cell optimized artifacts |
| `optimized_aggregate_artifact_name` | Optimized aggregate artifact name |
| `rebuild_source_workflow` | Workflow that produced inputs for manual rebuild |
| `deploy_base_path` | GitHub Pages base path passed to Astro as `ASTRO_BASE` |
| `deploy_site_url` | Optional full Pages URL passed to Astro as `ASTRO_SITE` |

Optimizer image: `config/images.nuon` exposes `helpers.media_optimizer`.
Override per run with `OCMTS_MEDIA_OPTIMIZER_IMAGE`.

The current pinned image is `linuxserver/ffmpeg:version-8.1-cli`; it
satisfies the v1 capability set (libwebp, libaom-av1, libvpx-vp9, libopus,
plus the avif, webp, and webm muxers).

## CLI surface

### `nu scripts/ocmts.nu artifacts probe-optimizer`

Resolves the configured optimizer image (or `--image <ref>`) and probes it
for the v1 capability set. Errors when an encoder or muxer is missing. Used
both as a manual diagnostic and as a strict gate inside `ci-site.yml`.

### `optimize-media`

```shell
nu scripts/ocmts.nu artifacts optimize-media --raw-dir <dir> --output-dir <dir>
```

Optimizes one cell artifact directory. Discovers
`cypress/screenshots/**/*.png`, `cypress/*.mp4` (MP4 placed directly under
the `cypress/` directory, as Cypress sometimes emits), and
`cypress/videos/**/*.mp4` (MP4 under `videos/` sub-directories) under
`<raw-dir>/artifacts/`. Converts each via the optimizer image, preserves
the run-relative path layout, and writes
`meta/optimized-media-cell.v1.json` in `<out-dir>`. Emits a
`no-source-media` manifest (with empty items) when the cell carries no
publishable media.

`--raw-dir` must be the directory that contains the `artifacts/` sub-tree
(for example the repo root `.` on a CI runner, or the artifact download
root). Passing `artifacts/` itself or a single cell directory will be
rejected with an error.

### `aggregate-optimized-media`

```shell
nu scripts/ocmts.nu artifacts aggregate-optimized-media \
  <dirs...> --output-dir <dir>
```

Reads downloaded `optimized-media-cell-*` directories, validates path
safety, kind/extension consistency, duplicate paths across cells, and
variant completeness (each `source_path` must have exactly one primary and
one fallback). Copies validated optimized media into `<out-dir>/artifacts/`
and writes `meta/optimized-media-summary.v1.json`. Pass `--no-archive` to
skip producing `optimized-media-artifacts.tar.zst` (used by local dev).

### `nu scripts/ocmts.nu site publish --optimized-media-dir <dir>`

Runs the site publish pipeline. `--optimized-media-dir` is optional. When
omitted and the public manifest contains screenshot or video evidence rows,
publish proceeds with the raw media and prints a warning to stderr. Pass
`--optimized-media-dir <dir>` to project the optimized aggregate (typically
the output of `aggregate-optimized-media`) into the public artifact tree
in place of the raw media.

### `nu scripts/ocmts.nu test cypress suite --publish-site [--optimize]`

Runs the matrix suite, then publishes. By default the suite publishes with
raw media; `site publish` prints a warning when the manifest contains media
rows but no optimized aggregate is provided. Pass `--optimize` to run
probe + per-cell optimize + aggregate before invoking `site publish`, so
the publish step receives the optimized aggregate.

## Manifest shapes

### Per-cell manifest (`meta/optimized-media-cell.v1.json`)

```json
{
  "schema_version": 1,
  "generated_at": "2026-05-10T12:58:01.123456789Z",
  "status": "optimized",
  "optimizer_image": "linuxserver/ffmpeg:version-8.1-cli",
  "items": [
    {
      "source_path": "artifacts/.../sample.png",
      "optimized_path": "artifacts/.../sample.avif",
      "kind": "screenshot",
      "status": "optimized",
      "role": "primary",
      "format": "avif",
      "mime": "image/avif"
    },
    {
      "source_path": "artifacts/.../sample.mp4",
      "optimized_path": "artifacts/.../sample.av1.webm",
      "kind": "video",
      "status": "optimized",
      "role": "primary",
      "format": "av1-webm",
      "mime": "video/webm",
      "codecs": "av01"
    }
  ]
}
```

For video items, `mime` and `codecs` are separate fields. For screenshot
items, `codecs` is omitted entirely.

### Aggregate summary (`meta/optimized-media-summary.v1.json`)

```json
{
  "schema_version": 1,
  "cells_found": 12,
  "cells_with_media": 10,
  "cells_without_media": 2,
  "cells_missing_manifest": 0,
  "item_counts": {
    "optimized": 84,
    "failed": 0
  },
  "cell_counts_by_status": {
    "no_source_media": 2,
    "missing_manifest": 0
  },
  "optimizer_images": ["linuxserver/ffmpeg:version-8.1-cli"],
  "cell_summaries": [ ... ]
}
```

`item_counts` describes individual derived files. `cell_counts_by_status`
describes whole cells. The two are independent; do not conflate them.

### Public projected evidence row (screenshot)

```json
{
  "kind": "screenshot",
  "scope": "cypress",
  "logical_name": "sample.avif",
  "path": "cypress/screenshots/sample.avif",
  "source_path": "cypress/screenshots/sample.png",
  "media_variants": [
    {
      "role": "primary",
      "path": "cypress/screenshots/sample.avif",
      "format": "avif",
      "mime": "image/avif"
    },
    {
      "role": "fallback",
      "path": "cypress/screenshots/sample.webp",
      "format": "webp",
      "mime": "image/webp"
    }
  ]
}
```

### Public projected evidence row (video)

```json
{
  "kind": "video",
  "scope": "cypress",
  "logical_name": "sample.av1.webm",
  "path": "cypress/videos/sample.av1.webm",
  "source_path": "cypress/videos/sample.mp4",
  "media_variants": [
    {
      "role": "primary",
      "path": "cypress/videos/sample.av1.webm",
      "format": "av1-webm",
      "mime": "video/webm",
      "codecs": "av01"
    },
    {
      "role": "fallback",
      "path": "cypress/videos/sample.vp9.webm",
      "format": "vp9-webm",
      "mime": "video/webm",
      "codecs": "vp9"
    }
  ]
}
```

`path` is the primary derived asset (what the site serves first).
`source_path` preserves raw provenance. `media_variants` is an ordered
array; renderers iterate and pick the first the browser supports.

## Failure semantics

Hard fail (publish aborts; no Pages deploy):

- Optimizer probe fails (missing encoder or muxer in the image).
- A required optimized variant is missing for any raw publishable evidence
  row (primary or fallback).
- The optimized aggregate contains an orphan file at a run-prefix path
  that no raw evidence row references.
- A path safety violation (absolute path, `..`, empty path) is detected at
  validate, aggregate, or projection time.
- A destination path computed during projection escapes the public root.

Soft (logged, lane continues):

- A cell with no publishable media: `status: no-source-media`, empty
  `items`. Aggregate counts the cell in `cell_counts_by_status.no_source_media`.
- Public manifest contains media rows but no optimized aggregate is
  provided to `site publish`: publish proceeds with raw media; a warning
  is printed to stderr.

Test execution failures are independent. On the publish branch, the CI
optimize lane still runs after the test step because the workflow step uses
`if: always() && github.ref == 'refs/heads/...'`. But optimization failures
inside that lane are now hard errors: the per-cell optimize command exits
nonzero on failed conversions, optimized artifact upload requires files, and
the site aggregate lane rejects empty or failed optimized summaries.

## Local development workflow

Default path (raw media; fast):

```shell
nu scripts/ocmts.nu test cypress suite \
  --publish-site \
  --site-dir ../ocm-web-site
```

The suite runs, then `site publish` ingests artifacts and builds the site.
Raw `.png` and `.mp4` are published as-is. `site publish` prints a warning
to stderr when the manifest contains media rows.

Web-optimized path (probe + optimize + aggregate + publish):

```shell
nu scripts/ocmts.nu test cypress suite \
  --publish-site --optimize \
  --site-dir ../ocm-web-site
```

With `--optimize` the suite, after running, performs:

1. `probe-optimizer-image` runs once with the resolved image; missing
   capabilities abort before any per-cell work.
2. Each cell run dir is staged into a per-cell tree and fed to
   `optimize-cell-media`.
3. Per-cell outputs are aggregated via `aggregate-optimized-media-cells`
   with `--no-archive` (no tar.zst needed locally).
4. The aggregate dir is passed to `site publish` as
   `--optimized-media-dir`.

The temp work dir is kept on failure for debugging; its path is printed at
the end of the run.

Astro smoke check (manual, optional):

```shell
cd ../ocm-web-site && bun run build
```

## CI workflow surface

`ci-run-cell.yml` per cell, gated on `publish_branch_gate`:

1. `Pre-pull optimizer image` warms the docker layer cache.
2. `Optimize cell media` runs `artifacts optimize-media --raw-dir .`
   (the runner working directory, which contains `artifacts/`) against
   the uploaded raw cell tree.
3. `Upload optimized media artifact` uploads
   `optimized-media-${{ inputs['artifact-name'] }}` (single
   `optimized-media-` prefix; the input already starts with `cell-`).

`ci-matrix.yml` keeps the raw aggregate job and delegates site work to
`ci-site.yml` via reusable workflow call.

`ci-site.yml`:

1. `prepare`: resolves the source workflow run id (caller-supplied for
   `workflow_call`, latest successful `ci-matrix.yml` for
   `workflow_dispatch`).
2. `aggregate-media`: probes the optimizer image, downloads
   `optimized-media-cell-*` from the source run, runs
   `artifacts aggregate-optimized-media`, uploads
   `optimized-media-summary`.
3. `build`: downloads `aggregate-summary` and `optimized-media-summary`,
   runs `site publish` with both inputs, builds the Astro site, uploads
   the Pages artifact.
4. `deploy`: deploys the Pages artifact.

## Manual rebuild

`workflow_dispatch` on `ci-site.yml` rebuilds the site from a previous
matrix run without rerunning tests. The dispatch resolves the latest
successful `ci-matrix.yml` run on the configured publish branch and
downloads its raw and optimized artifacts. Useful when the renderer or the
projection logic changes but the test evidence does not.

## See also

- `docs/architecture/media-projection.md` for the design rationale (raw
  vs derived, format choices, two-lane parallel justification).
- `docs/operations/site-publish.md` for the broader site publish lane.
- `scripts/lib/artifacts/` for the optimize and aggregate implementations.
- `scripts/lib/site/project-media.nu` for the projection rules.
- `scripts/tests/fixtures/optimized-media/README.md` for the integration
  test fixture layout.
