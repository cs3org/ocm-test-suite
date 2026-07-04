/// <reference types="cypress" />

import type { ActorCredentials } from "../contracts/login";
import { takeEvidenceScreenshot } from "./evidence";

const idpFormTimeoutMs = 30000;

export type IdpSessionArgs = {
  idpOrigin: string;
  realm: string;
  credentials: ActorCredentials;
  // When set, capture the login-page-ready evidence inside the session setup
  // (i.e. while the IdP form is on the primary origin, so cy.screenshot is safe).
  scenarioId?: string;
};

// Authenticate at the Keycloak account console on the IdP origin as a
// first-class navigation target: the form is same-origin so there is no
// cy.origin and no cross-origin screenshot crash. The realm SSO cookie is
// cached with cy.session so the app can complete a silent OIDC handshake on
// cy.visit("/"). The session key is [idpOrigin, username]; per-party IdP
// origins (idp1.docker / idp2.docker) keep multi-instance logins isolated.
export function establishIdpSession(args: IdpSessionArgs): void {
  const { idpOrigin, realm, credentials, scenarioId } = args;
  const { username, password } = credentials;

  cy.session(
    [idpOrigin, username],
    () => {
      cy.visit(`${idpOrigin}/realms/${realm}/account`);

      cy.get("form#kc-form-login", { timeout: idpFormTimeoutMs }).should(
        "be.visible",
      );

      if (scenarioId) {
        takeEvidenceScreenshot({
          scenarioId,
          sequence: 1,
          actor: "single",
          checkpoint: "login-page-ready",
        });
      }

      cy.get("form#kc-form-login")
        .should("be.visible")
        .within(() => {
          // Selectors pinned to the Keycloak 26.x keycloak.v2 theme; no name=
          // fallbacks so theme drift fails fast instead of silently.
          cy.get("input#username").clear().type(username);
          cy.get("input#password").clear().type(password, { log: false });
          cy.get("button#kc-login").should("be.enabled").click();
        });

      // Landing back in the account console (form gone) means the realm SSO
      // session is established and cached.
      cy.get("form#kc-form-login").should("not.exist");
    },
    {
      cacheAcrossSpecs: true,
    },
  );
}
