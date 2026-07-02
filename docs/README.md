# OCM Test Suite Docs

This directory holds the human-readable contracts for the OCM Test Suite.
The root `README.md` stays focused on quickstart usage; docs here explain the
architecture and authoring rules that should remain stable across flows.

## Evidence And Publishing

- `architecture/evidence-standard.md` defines artifacts, evidence, published
  evidence, screenshot naming, and retention policy.
- `testing/cypress-evidence.md` explains how Cypress tests capture proof
  screenshots and how evidence names must be formed.
- `testing/contact-token-platforms.md` records the actor and provider JSON
  contracts for Reva-based contact-token cells.
- `operations/site-publish.md` documents the run-to-site path for artifacts,
  manifests, CI aggregation, and public publication.
- `operations/optimized-media.md` documents the AVIF/WebP/WebM optimized
  media lane, configuration, CLI commands, and CI workflow surface.
- `operations/cli.md` documents the CLI entry point and common local run flows.
- `operations/configuration.md` documents image overrides, actors,
  execution subnet and `ocmgo` route env contracts, and Cypress env
  conventions.

## Architecture

- `architecture/evidence-standard.md` for the broader evidence contract.
- `architecture/media-projection.md` for the raw-vs-derived publish
  projection rationale and format choices.
- `architecture/tuple-identity.md` for the `flow_id` vs `matrix_key` vs
  `cell_id` vocabulary, the tuple naming convention, and operator recipes
  for the explicit `--flow` + platform/version flags.

## Implementation Pointers

- Cypress flow code lives under `cypress/e2e/`.
- Cypress shared support lives under `cypress/support/`.
- Artifact envelope generation lives in `scripts/lib/publish-envelope.nu`.
- Site ingestion lives in `scripts/lib/site-ingest.nu`.
- CI aggregation lives in `scripts/lib/ci/aggregate.nu`.
- Optimized media production lives in `scripts/lib/artifacts/`.
- Public media projection lives in `scripts/lib/site/project-media.nu`.

## CI workflow configuration

CI workflow generation SSOT lives under `config/ci/`. See `config/ci/README.md`.
