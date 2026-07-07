# Contributing

Thanks for taking a look at the OCM Test Suite. Whether you want to fix a flaky
flow, add a platform, tighten the evidence pipeline, or improve the docs, your
help is welcome here.

This repo is config-first and automation-heavy, so the most useful thing this
guide can do is show you where things live and how not to fight the machinery.

## The mental model

- This repo runs interoperability tests and turns them into evidence.
- It does not build the platform images (those come from
  [MahdiBaghbani/containers](https://github.com/MahdiBaghbani/containers), the
  DockyPody image fleet).
- It does not host the Observatory UI (that is
  [MahdiBaghbani/ocm-web-site](https://github.com/MahdiBaghbani/ocm-web-site));
  this repo builds and deploys it from CI.
- It is not the OCM spec ([cs3org/OCM-API](https://github.com/cs3org/OCM-API)).

## Local setup

Prereqs:

- Nushell (`nu`)
- Docker (and Docker Compose)
- Bun (used for the TypeScript sidecars and CI preflight)

Start here:

```sh
nu scripts/ocmts.nu
nu scripts/ocmts.nu test units
```

`test units` runs fast, Docker-free checks of the automation logic and is the
quickest way to know you did not break the CLI.

## Config-first changes

Most changes are configuration, not hand-written glue. A few common cases:

- Change matrix rules or platforms: edit `config/matrix/*`, then regenerate
  derived artifacts (Cypress matrix and CI workflows) and run the drift checks.
- Bump an image: edit `config/images.nuon` (the images themselves live in the
  containers repo).
- Add or change an adapter: update the Cypress adapter registry and the
  capability registry in `config/adapters/`.
- Change actors or credentials: edit `config/actors/`.

Generated files (CI workflows, workflow assets, generated Cypress matrix files)
should not be hand-edited. Regenerate them instead. See
[config/ci/README.md](config/ci/README.md) and
[scripts/README.md](scripts/README.md) for the exact commands.

## Before you open a pull request

Run the checks that CI will run:

- `nu scripts/ocmts.nu test units`
- the workflow generation and drift checks (see `config/ci/README.md`)
- the capability check for matrix changes

If your change touches a flow end to end, run at least one relevant cell locally
and confirm the evidence looks right.

## Evidence rules

Evidence is the product here, so keep it trustworthy. See
[docs/architecture/evidence-standard.md](docs/architecture/evidence-standard.md)
for the contract, and the Cypress policies (no `allowCypressEnv`, isolation
rules, IdP session handling) documented under
[docs/operations/configuration.md](docs/operations/configuration.md).

## Pull requests

- Keep pull requests focused.
- Say whether the change touches a flow, the matrix, the CI generation, or the
  evidence pipeline.
- Call out cross-repo implications (images in `containers`, UI in
  `ocm-web-site`).
- Update the docs when behavior changes.

## Questions and issues

Questions, bug reports, and ideas are welcome on the
[issue tracker](https://github.com/cs3org/ocm-test-suite/issues). If you are
planning a larger change, opening an issue first to talk it through saves
everyone time.

By contributing, you agree that your contributions are licensed under
AGPL-3.0-or-later, consistent with this repository.
