// Centralized cy.origin() policy for the OCM test suite.
// cy.origin() is banned except for the bounded specs and call sites listed here.
// The runtime overwrite in cypress/support/e2e.ts and the static AST guard in
// scripts/typescript/cross-origin-policy.test.ts both source from this module.

export const CROSS_ORIGIN_ALLOWED_SPECS = [
  "cypress/e2e/contact-wayf/index.cy.ts",
  "cypress/e2e/webapp-share/index.cy.ts",
] as const;

export const CROSS_ORIGIN_ALLOWED_CALL_SITE_FILES = [
  "cypress/support/shared/jupyter-ui-proof.ts",
  "cypress/support/adapters/nextcloud/v35/contact-adapter.ts",
  "cypress/support/adapters/nextcloud/v34/contact-adapter.ts",
] as const;

export const CROSS_ORIGIN_POLICY_TEXT = [
  "cy.origin() is forbidden in this test suite.",
  "Rule: split sender and receiver work into separate tests.",
  "External IdP login must use cy.session() via idp-session.ts, not cy.origin().",
  "Bounded exceptions: contact-wayf may use cy.origin() only to capture the receiver redirect URL after WAYF discovery; webapp-share may use cy.origin() only for the terminal JupyterLab visual-proof assertion after launch-gate work. It must not drive login, accept, contact proof, or share flows.",
].join(" ");
