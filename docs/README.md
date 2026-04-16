# OTS Docs

This directory holds the human-readable contracts for the OCM Test Suite.
The root `README.md` stays focused on quickstart usage; docs here explain the
architecture and authoring rules that should remain stable across flows.

## Evidence And Publishing

- `architecture/evidence-standard.md` defines artifacts, evidence, published
  evidence, screenshot naming, and retention policy.
- `testing/cypress-evidence.md` explains how Cypress tests capture proof
  screenshots and how evidence names must be formed.
- `operations/site-publish.md` documents the run-to-site path for artifacts,
  manifests, CI aggregation, and public publication.

## Implementation Pointers

- Cypress flow code lives under `cypress/e2e/`.
- Cypress shared support lives under `cypress/support/`.
- Artifact envelope generation lives in `scripts/lib/publish-envelope.nu`.
- Site ingestion lives in `scripts/lib/site-ingest.nu`.
- CI aggregation lives in `scripts/lib/ci/aggregate.nu`.
