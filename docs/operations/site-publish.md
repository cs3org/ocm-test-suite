# Site Publish

The OCM Test Suite publishes test evidence by carrying run artifacts through a
small number of stable stages: Cypress writes files, the run envelope indexes
evidence, CI aggregates envelopes, and site ingest copies the published evidence
set.

## Local Run Path

`nu scripts/ocmts.nu services up run ...` creates:

```text
artifacts/<flow_id>/<pair>/<execution_id>/
```

The Cypress container writes into that directory through `/artifacts`.
Important paths:

- `cypress/screenshots/`
- `cypress/videos/`
- `cypress/downloads/`
- `docker/logs/`
- `meta/`

At the end of a terminal run, `ocmts` writes:

- `meta/run.json`
- `meta/result.json`
- `meta/suite-manifest.v1.json`
- `meta/summary.json`
- `meta/summary.md`

`meta/suite-manifest.v1.json` is the run evidence envelope.

## CI Path

Each CI cell uploads the full `artifacts/` tree for that cell. The matrix
workflow downloads cell artifacts, aggregates their run envelopes, writes the
suite aggregate under `artifacts/suites/aggregated/`, and creates the archive
used by the site-publish job.

The aggregate step must preserve screenshot, video, log, metadata, and MITM
evidence rows from the selected run for each cell.

## Site Ingest

Site ingest reads a suite record and imports the latest terminal result for
each cell. It writes public data files such as:

- `suite-manifest.v1.json`
- `matrix-rules.v1.json`
- `implemented-cells.v1.json`

It also copies published evidence into:

```text
public/artifacts/<flow_id>/<pair>/<execution_id>/
```

Published evidence includes metadata, screenshots, videos, Docker logs, MITM
flows, and MITM reports. Downloads remain local/per-run evidence and are not
copied to the public site by default.

## Optimized Media Projection

Public screenshots and videos in the published tree are derived assets
(AVIF + WebP for screenshots, AV1 WebM + VP9 WebM for videos), not the raw
PNG and MP4 captured by Cypress. The raw bytes remain available in raw
artifacts and the raw aggregate. In the CI publish lane, raw media is not
exposed under `public/artifacts/`; OTS rewrites the public manifest so media
rows point at the derived files while keeping `source_path` set to the raw
provenance. For local/manual `site publish` without `--optimized-media-dir`,
raw media may still be published as a fallback.

For commands, configuration, manifest shapes, the CI workflow surface, and
the local development workflow, see
`docs/operations/optimized-media.md`. For the design rationale (raw vs
derived, format choices, two-lane parallel design), see
`docs/architecture/media-projection.md`.

## Latest-Per-Cell Rule

The site is a review surface, not a retry browser. It presents the latest
terminal result for each cell. Older attempts may remain in local artifacts,
CI archives, or suite records, but they should not appear as first-class cells
in the public manifest.

## Pruning

Screenshots are primary proof evidence and should be retained. Videos and
Docker logs are supporting evidence and may be pruned by explicit artifact
maintenance commands when storage pressure matters.

After pruning, regenerate the run envelope so evidence counts and paths match
the remaining files.

Pruning raw evidence does not regenerate the public site. Public derived
media is built from the optimized aggregate during a publish run; if you
prune raw and want the public site to match, rerun the suite or trigger a
manual rebuild via `ci-site.yml`.

## Operator Guidance

- Do not pass `--no-video` when the run is meant for manual review or publish.
- Use `--no-video` only for fast local checks.
- Check `meta/summary.md` for evidence counts after a run.
- If site output seems incomplete, inspect the run envelope first, then the
  site ingest copy step.
