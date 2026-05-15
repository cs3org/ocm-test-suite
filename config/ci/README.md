# config/ci/

CI workflow generation inputs. All three files are strict JSON inside a
`.nuon` extension so the editor lints them as JSON5 (via `.gitattributes`)
while `nu open` still parses them as nuon.

## Regenerating workflows

After editing any file in this directory, regenerate the workflow YAMLs:

```sh
nu scripts/ocmts.nu ci workflows generate github
```

Then verify no drift between blueprints and rendered output:

```sh
nu scripts/ocmts.nu ci workflows check github
```

## Files

### `prerequisites.nuon`

Capability rules that drive `depends_on` edges between cells in the
generated matrix. The planner reads these rules to figure out which
cells must complete before a downstream cell can run.

Top-level shape:

```jsonc
{ "capability_rules": [ <rule>, ... ] }
```

Each rule:

- `capability_flow` (string): the flow that produces one capability per
  `platform/version` pair. With `"login"`, every login cell produces a
  capability named `login__<platform>-<version>` (for example
  `login__nextcloud-v34`).
- `required_for_flows` (string[]): flows whose cells consume the
  capability above. A cell in one of these flows that uses a given
  `platform/version` for a participant role (see `required_roles`)
  depends on the corresponding login cell.
- `required_roles` (string[]): which participant roles trigger the
  dependency. `"sender"` means the sender's `platform/version` must have
  the capability; `"receiver"` means the receiver's must.

### `toolchain.nuon`

Pinned tool versions used in generated GitHub workflows. Bumping a
version here regenerates the corresponding `with: version:` block in
every job that installs that tool.

Fields:

- `nushell.version` (string): exact Nushell release to install with
  `hustcer/setup-nu@v3` in every job.

### `workflows.nuon`

GitHub Actions surface config: filenames, runner image, action pins, and
visual ordering.

Fields under `github`:

- `filenames.matrix` (string, default `"ci-matrix.yml"`): output basename
  for the matrix orchestrator workflow.
- `filenames.run_wave` (string, default `"ci-run-wave.yml"`): output
  basename for the reusable wave workflow.
- `filenames.run_cell` (string, default `"ci-run-cell.yml"`): output
  basename for the reusable cell workflow.
- `filenames.site` (string, default `"ci-site.yml"`): output basename for
  the site publish workflow.

  All four keys are optional; the defaults above apply when a key is
  absent. Both the generator (`ci workflows generate github`) and the
  checker (`ci workflows check github`) resolve output and expected paths
  from the configured basenames, so renaming a key takes effect in both
  commands without extra configuration.

- `runner` (string): the `runs-on:` label baked into every job.
- `setup_nu_action` (string): the action used to install Nushell.
  Bumping this pin updates every workflow that installs nu.
- `action_checkout` (string): the `actions/checkout` pin used in every
  workflow.
- `action_upload_artifact` (string): artifact upload action pin used in
  ci-matrix.yml, ci-run-cell.yml, and ci-site.yml.
- `action_download_artifact` (string): artifact download action pin used
  in ci-matrix.yml and ci-site.yml.
- `action_upload_pages_artifact` (string): Pages artifact upload pin used
  in ci-site.yml.
- `action_deploy_pages` (string): Pages deploy action pin used in
  ci-site.yml.
- `action_setup_bun` (string): Bun setup action pin used in ci-matrix.yml
  and ci-site.yml.
- `max_parallel` (int, optional): when set to a positive integer, adds a
  `max-parallel:` constraint to the matrix strategy in ci-run-wave.yml.
  Omit or set to `0` to disable the constraint (default behavior).
- `job_order` (string[]): visual ordering for cell-group jobs in the
  matrix workflow. Cells are sorted by their flow's position in this
  list; flows not listed appear after all listed flows in their natural
  order.
