# Media Projection

The OCM Test Suite separates raw test evidence from derived publish
evidence. Raw is the test truth; derived is a publication projection. This
document explains why the boundary exists and why the formats and lanes
are the way they are.

For the operational surface (commands, configuration, manifest shapes,
failure modes), see `docs/operations/optimized-media.md`.

## Raw vs derived: separation of truth

Raw evidence captures what the tests produced: PNG screenshots and MP4
recordings written by Cypress, plus logs and metadata. The raw
`meta/suite-manifest.v1.json` describes raw evidence and is never
rewritten by the publish lane. This keeps raw artifacts honest as a
debugging surface; an operator triaging a failure can trust that the
manifest paths point at the bytes the test wrote.

Derived evidence is everything the public site serves. The public manifest
is a projection of the raw manifest with media rows rewritten to point at
optimized variants. Raw bytes are not a public fallback; the public tree
contains derived bytes only.

Mixing the two would corrupt provenance. If the raw manifest mentioned
optimized variants, future debuggers could not tell whether a path
described a captured byte or a derived byte. If raw bytes leaked into the
public tree as fallbacks, the site would silently regress to old formats
on partial pipeline failures and operators would not notice.

The contract therefore enforces the boundary in both directions:

- the optimize and aggregate steps never touch raw artifacts;
- the projection step never touches the raw manifest;
- the publish hard-fails when required derived variants are missing
  rather than serving raw fallbacks.

## Two-lane parallel design

A serial post-aggregate optimizer would let one ffmpeg job decide the
publish latency for the whole suite. The OCM matrix already runs cells
in parallel; serializing media work would convert that parallel shape
into a single late bottleneck.

The optimized-media lane lives beside each cell. `ci-run-cell.yml`
optimizes one cell's media right after that cell's tests finish, in the
same runner that already has the raw output on disk. The cell uploads its
optimized output as `optimized-media-<artifact-name>`, parallel with the
raw `cell-<key>` upload. `ci-site.yml` aggregates both lanes once they
finish, in its own job.

This split has three effects:

- Pages publish latency tracks the slowest cell, not the sum of cells.
- A late ffmpeg failure cannot block the raw aggregate path.
- Manual rebuild can reuse a previous matrix run's optimized cell
  artifacts without re-running tests.

## Format choices in v1

Public screenshots:

- Primary: AVIF (better compression than WebP at typical screenshot
  resolution; widely supported by current Chromium and Firefox).
- Fallback: WebP (broader support floor for slightly older browsers).
- No PNG fallback. Public PNG would defeat the storage savings and
  obscure when the AV1 path failed.

Public videos:

- Primary: AV1 in WebM (smaller than VP9 at equivalent quality; supported
  by current Chrome and Firefox).
- Fallback: VP9 in WebM (broad support floor).
- No MP4 fallback. The optimized lane targets reviewer-grade evidence on
  modern browsers; H.264 MP4 is only kept in raw artifacts for debugging.

Browser baseline is an explicit, accepted product choice. Operators on
older browsers should consume the raw artifact via the test pipeline, not
the published site.

## Why the public manifest changes

`path` becomes the primary derived asset path. This is what the site
serves first; the manifest tells the consumer what is actually being
served, not what was originally captured.

`source_path` preserves the raw captured path so the public manifest
remains honest about provenance. A reviewer reading the public manifest
can see both the served file and the source it came from.

`media_variants` is an ordered array. The renderer iterates it in order
and picks the first variant the browser supports. This is the honest
representation of a `picture` or `video` element with multiple `source`
children; a single `path` field cannot express variant negotiation.

`logical_name` is rewritten to the derived public filename so it matches
what the site actually serves under that row. Keeping the raw filename
here would cause downloads and references to disagree with the served
bytes.

Non-media evidence (logs, metadata, MITM JSON) keeps its original public
path because there is no derived variant.

## Failure stance

The contract treats missing required optimized variants as a hard failure
of the publish lane. The reasoning:

- A successful build with a missing AV1 video would silently degrade the
  site, hiding the underlying ffmpeg or pipeline failure.
- The aggregate step already validates variant completeness; reaching
  publish with missing variants means the validation gap was somewhere
  upstream and the operator needs to know.
- Pages deploy is gated on the publish branch, so the cost of a hard
  fail is "the site does not refresh on this push," which is recoverable.

The cost of soft failure (degraded site) is higher than the cost of hard
failure (no site update). The contract picks hard fail.

## See also

- `docs/operations/optimized-media.md` for commands, configuration,
  manifest shapes, and CI surface.
- `docs/architecture/evidence-standard.md` for the broader evidence
  contract.
- `docs/operations/site-publish.md` for the raw site publish lane.
