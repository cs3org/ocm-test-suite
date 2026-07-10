# OCM Test Suite

> Proof, not promises: end-to-end Open Cloud Mesh interoperability tests across
> real platforms, with the screenshots, logs, and traffic to back every result.

[![Ask DeepWiki](https://deepwiki.com/badge.svg)](https://deepwiki.com/cs3org/ocm-test-suite)
[![License: AGPL-3.0](https://img.shields.io/badge/license-AGPL--3.0-blue.svg)](LICENSE.md)

Interoperability is easy to claim and hard to show. This repo exists to show it.
It stands up real Open Cloud Mesh (OCM) platforms in Docker, drives real
browser flows between them, and captures what actually happened as reviewable
evidence. Then it publishes the whole thing as a browsable compatibility matrix.

- Live results: <https://cs3org.github.io/ocm-test-suite/>
- Observatory: <https://cs3org.github.io/ocm-test-suite/observatory/>

This is the engine behind the OCM Observatory. It is not the OCM specification
(that lives in [cs3org/OCM-API](https://github.com/cs3org/OCM-API)), and it is
not the Observatory website (that lives in
[MahdiBaghbani/ocm-web-site](https://github.com/MahdiBaghbani/ocm-web-site)).
What it owns is the hard part in the middle: running the tests and turning them
into evidence anyone can inspect.

## Why this matters

When someone says "platform A and platform B interoperate over OCM," what does
that actually mean? Which flow? Which versions? And can you see it, or do you
have to take it on faith?

This suite answers those questions with artifacts. Every run captures
screenshots, video, container logs, run metadata, and, for the protocol-heavy
flows, the actual OCM traffic through a MITM proxy. A red or green box is never
the end of the story here; you can open a cell and see exactly what happened.

## What it tests today

Real UI flows against real containerized stacks, not mocked APIs:

- Platforms: Nextcloud, oCIS, OpenCloud, CERNBox, and OpenCloudMesh Go
- Flows: `login`, `share-with`, `contact-token`, `contact-wayf`, `webapp-share`
- More than 50 matrix cells run in CI, Chrome-first

Coverage is deliberately explicit. Not every platform supports every flow, and
the suite tracks that honestly with a capability registry rather than hiding
gaps. What is supported, what is pending, and what a vendor does not support are
all first-class states.

## How it works

The suite is driven by a Nushell CLI (`ocmts`) over a config-first design:

1. You pick a tuple: a flow, a sender platform and version, and (for two-party
   flows) a receiver.
2. `ocmts` resolves the matrix cell, generates Docker Compose overlays, and
   brings the stacks up.
3. It runs the Cypress flow in a container, wiring MITM capture where relevant.
4. It collects artifacts into a structured evidence envelope, then tears down.
5. In CI, results are aggregated across the matrix and published to the
   Observatory.

The CI itself is generated from config, with drift checks, so the matrix stays
consistent instead of drifting into hand-maintained YAML.

## Quick start

Prereqs:

- Nushell (`nu`)
- Docker (and Docker Compose)

Discover commands:

```sh
nu scripts/ocmts.nu
nu scripts/ocmts.nu services up run --help
nu scripts/ocmts.nu test cypress suite --help
```

Run a single cell locally (brings up services, runs Cypress, collects
artifacts, then tears down unless `--keep-up`):

```sh
nu scripts/ocmts.nu services up run ...
```

Run the full enabled suite locally:

```sh
nu scripts/ocmts.nu test cypress suite ...
```

Run fast internal unit tests (no Docker):

```sh
nu scripts/ocmts.nu test units
```

Heads up: the full suite pulls multi-container images and is resource-heavy.
For one-cell runs and the exact flags, see `docs/operations/cli.md`.

## Where to read next

- Docs index: [docs/README.md](docs/README.md)
- CLI and local runs: [docs/operations/cli.md](docs/operations/cli.md)
- Configuration (images, actors, Cypress env):
  [docs/operations/configuration.md](docs/operations/configuration.md)
- Flow identity (tuple + matrix_key):
  [docs/architecture/tuple-identity.md](docs/architecture/tuple-identity.md)
- Evidence and publication:
  [docs/architecture/evidence-standard.md](docs/architecture/evidence-standard.md),
  [docs/operations/site-publish.md](docs/operations/site-publish.md)
- Automation layout: [scripts/README.md](scripts/README.md)
- CI workflow generation: [config/ci/README.md](config/ci/README.md)

## DeepWiki

If you want a browsable, AI-generated map of this repository, see
[DeepWiki](https://deepwiki.com/cs3org/ocm-test-suite). It is a fast way to get
oriented across the CLI, matrix, and evidence pipeline, but the files under
[`docs/`](docs/) are still the source of truth.

## Ecosystem

This suite sits in the middle of the OCM stack:

- Spec under test: [cs3org/OCM-API](https://github.com/cs3org/OCM-API)
- Platform images it runs:
  [MahdiBaghbani/containers](https://github.com/MahdiBaghbani/containers)
  (DockyPody), published to `ghcr.io/mahdibaghbani/containers/*`
- Results UI it feeds:
  [MahdiBaghbani/ocm-web-site](https://github.com/MahdiBaghbani/ocm-web-site)
  (the Observatory)
- A peer implementation in the same effort:
  [MahdiBaghbani/opencloudmesh-go](https://github.com/MahdiBaghbani/opencloudmesh-go)

Under test alongside those: Nextcloud, oCIS, OpenCloud, and CERNBox.

## History and credits

This project has a long history. It started in 2023 as an earlier OCM and EFSS
interoperability lab and grew a large body of practical Docker, Reva, and
Cypress testing knowledge. In 2026 it was deliberately rebuilt into the current
`ocmts` harness: config-driven matrix rules, a tuple identity model, structured
evidence, generated CI, and the publish pipeline behind the Observatory.

- Started by Michiel de Jong, who founded the project and led its early
  direction.
- Major historical CERNBox and Reva contributions from Giuseppe Lo Presti,
  which brought the CERN-side stack into the picture.
- Built into its current form primarily by Mahdi Baghbani, who leads the modern
  architecture and rewrite, with contributions from other OCM collaborators.

## Acknowledgements

This work exists because a few organizations chose to fund open source
interoperability. A big thank you to NLnet and the Sovereign Tech Agency for
backing the Open Cloud Mesh work behind this suite, which Mahdi Baghbani
maintains.

<p>
  <a href="https://nlnet.nl/project/OpenCloudMesh/">
    <img alt="NLnet Foundation" src="assets/logos/funders/nlnet.svg" height="64">
  </a>
  &nbsp;&nbsp;&nbsp;
  <a href="https://www.sovereign.tech/tech/open-cloud-mesh">
    <img alt="Sovereign Tech Agency" src="assets/logos/funders/sovereign-tech-agency.svg" height="64">
  </a>
</p>

You can read the full story in [FUNDING.md](FUNDING.md).

## Contributing

Contributions are welcome. See [CONTRIBUTING.md](./CONTRIBUTING.md) for the local
workflow, the config-first change model, and what makes review easy.

## License

Licensed under the GNU Affero General Public License v3.0 or later
(AGPL-3.0-or-later). See [LICENSE.md](LICENSE.md).
