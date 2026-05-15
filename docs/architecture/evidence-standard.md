# Evidence Standard

The OCM Test Suite treats screenshots, videos, logs, metadata, and selected
protocol captures as test evidence. Evidence is not a replacement for
assertions; it is the reviewable record that lets a human understand what a run
proved after the containers are gone.

## Terms

- Artifact: any file written under
  `artifacts/<flow_id>/<pair>/<execution_id>/`.
- Evidence: an artifact that is listed in the run's
  `meta/suite-manifest.v1.json` under `results[].evidence[]`.
- Published evidence: evidence copied into the site `public/artifacts/` tree
  and referenced by the public suite manifest.
- Proof screenshot: an explicit success screenshot taken at a user-visible
  checkpoint after the test has reached or asserted that state.
- Supporting evidence: videos, Docker logs, MITM files, and metadata that help
  explain or debug the proof.

## Artifact Tree

Each run writes one execution directory:

```text
artifacts/<flow_id>/<pair>/<execution_id>/
  compose/
  cypress/
    downloads/
    screenshots/
      <spec-name>/
    videos/
  docker/logs/
  meta/
```

The run envelope lives in `meta/suite-manifest.v1.json`. It is the single
source of truth for evidence rows. Summaries and site outputs are projections
of that envelope.

The per-cell evidence master sidecar is `meta/evidence.v1.json`. It
enumerates every evidence item with a typed `envelope` kind so renderers
can dispatch without sniffing file contents:

| Envelope kind     | Used for                                     |
| ----------------- | -------------------------------------------- |
| `text-log.v1`     | Plain-text logs (cypress-run.log, platform.log, MITM `mitm/logs/*.log` when present) |
| `jsonl.v1`        | Newline-delimited JSON records (one record = one row) |
| `event-stream.v1` | MITM `mitm/flows/traffic.jsonl` (request/response pairs) |
| `markdown.v1`     | MITM markdown reports under `mitm/reports/*.md` |
| `stub.v1`         | Lightweight pointer envelope (e.g. videos, screenshots that the site renders directly) |

`items[]` is filtered to paths that physically exist on disk, so
consumers can trust that every listed item is fetchable. Companion
sidecars (`meta/result.v1.json`, `meta/images.v1.json`,
`compose/manifest.v1.json`, `mitm/startup.v1.json`,
`mitm/connect-errors.v1.jsonl`) carry their own structured records and are
referenced from the master sidecar.

## Evidence Classes

| Class | Local artifact | Manifest evidence | Site artifact | Policy |
| --- | --- | --- | --- | --- |
| Metadata | yes | yes | yes | Always published with the run. |
| Screenshots | yes | yes | yes | Primary proof evidence. |
| Videos | yes | yes | yes | Published by default; use `--no-video` only for fast local checks. |
| Docker logs | yes | yes | yes | Supporting debug evidence. The mitm container log itself is no longer collected; mitm activity is captured via the `mitm/flows/` and `mitm/reports/` evidence below. |
| MITM flows and reports | yes | yes | yes | Supporting protocol evidence for MITM flows (`traffic.jsonl`, `session.json`, derived reports under `mitm/reports/`, plus `startup.v1.json` and `connect-errors.v1.jsonl`). |
| Downloads | yes | yes | no | Local/per-run evidence only unless a future site feature needs them. |
| Compose inputs | yes | yes (`compose/manifest.v1.json` only) | yes (manifest only) | Reproducibility artifact; the structured manifest is published, the raw rendered files are not. |

## Screenshot Naming

Explicit proof screenshots must use this shape:

```text
<cell_id>--<NNN>--<actor>--<checkpoint>.png
```

- `cell_id` is the generated matrix cell id, for example
  `login__opencloud-v6`.
- `NNN` is a zero-padded sequence number within the scenario run.
- `actor` is `single`, `sender`, or `receiver`.
- `checkpoint` is a lowercase semantic name such as `login-page-ready`,
  `authenticated`, `share-saved`, or `share-visible`.

Examples:

```text
login__opencloud-v6--001--single--login-page-ready.png
login__opencloud-v6--002--single--authenticated.png
share-with__nextcloud-v34__nextcloud-v34--001--sender--authenticated.png
share-with__nextcloud-v34__nextcloud-v34--004--receiver--share-visible.png
```

Do not rely on Cypress duplicate filename suffixing. Names must be unique and
sortable before Cypress writes the file.

## Video Naming

Cypress creates videos from spec names. `ocmts` normalizes proof-run videos to:

```text
<cell_id>--run.mp4
```

Videos are secondary evidence, but they are published by default because they
are important for manual review.

If Cypress writes the video under its spec filename, `ocmts` renames that file
before writing the run envelope.

## Run Selection For The Site

The site presents the latest terminal result for each cell. Older attempts may
remain in local artifacts or suite archives, but the public suite manifest is
latest-per-cell. This keeps the site readable and avoids turning retries into
a second review dimension.

## Safety Rules

- Never screenshot a password after it has been typed unless the UI masks it.
- Prefer screenshots after assertions, not before them.
- Runtime JSON writes are not user-visible checkpoints and should not drive
  proof screenshots.
- Logs and MITM files are test/development evidence. They are useful for review
  and debugging, but they should not be described as production redaction-safe
  material.
