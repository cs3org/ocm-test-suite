# Cypress Evidence

Cypress tests must capture proof screenshots at strategic, user-visible
checkpoints. The assertions still decide pass or fail; screenshots and videos
make the result reviewable after the run.

## Required Helper

Flow steps should use one shared evidence helper from `cypress/support/shared/`.
Do not add local `cy.screenshot(...)` wrappers in individual flow files.

The helper owns:

- filename shape
- numeric ordering
- actor/checkpoint validation
- future metadata conventions

## Filename Contract

Screenshots use:

```text
<cell_id>--<NNN>--<actor>--<checkpoint>
```

Cypress adds the `.png` extension. `cell_id` must be the same id used by
`CYPRESS_proof_cell`, `meta/cell.json`, and the suite manifest.

Allowed actors:

- `single` for one-party flows such as login
- `sender` for sender-side work
- `receiver` for receiver-side work

Use semantic checkpoints, not UI widget names. Good examples:

- `login-page-ready`
- `authenticated`
- `share-saved`
- `share-visible`
- `invite-created`
- `invite-accepted`
- `contact-visible`

## Flow Checkpoints

### Login

Every login cell must capture:

1. `single/login-page-ready` before credentials are typed
2. `single/authenticated` after the adapter has asserted login success

This covers Nextcloud, OCMGo, oCIS, and OpenCloud through the shared login
scenario layer.

### Share With

Every share-with cell must capture:

1. `sender/authenticated`
2. `sender/share-saved`
3. `receiver/authenticated`
4. `receiver/share-visible`

If a platform performs part of the setup without a visible browser state, do
not fake a screenshot for that setup step. Capture the next visible state.

### Contact Token

Contact-token cells must capture:

1. `sender/authenticated`
2. `sender/invite-created`
3. `receiver/authenticated`
4. `receiver/invite-accepted`
5. `receiver/contact-visible`
6. `sender/share-saved`
7. `receiver/share-visible`

Do not capture a separate screenshot only because a runtime file was written.
Runtime files support the procedure; they are not visual proof.

### Contact WAYF

Contact-WAYF cells must capture:

1. `sender/authenticated`
2. `sender/invite-created`
3. `receiver/authenticated`
4. `receiver/invite-accepted`
5. `receiver/contact-visible`
6. `sender/share-saved`
7. `receiver/share-visible`

The `cy.origin()` exception remains limited to redirect capture. Do not broaden
that exception to login, invite accept, contact proof, or sharing.

## Videos

Videos are enabled by default for proof runs. Use `--no-video` only for fast
local checks where manual review is not the goal.

The proof video for a cell should be normalized to:

```text
<cell_id>--run.mp4
```

OTS performs that normalization after Cypress finishes, before the evidence
envelope is written.

## Review Checklist

- Does each passing flow produce at least one proof screenshot?
- Are screenshot names sortable and unique without Cypress suffixes?
- Does every screenshot correspond to a user-visible state?
- Are passwords and secrets hidden?
- Does the video name include the `cell_id`?
- Do manifest evidence rows point to the screenshots and video?
