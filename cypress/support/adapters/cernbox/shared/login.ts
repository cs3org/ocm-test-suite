/// <reference types="cypress" />

import type { ActorCredentials } from "../../../contracts/login";
import { establishIdpSession } from "../../../shared/idp-session";

// CERNBox web is an ownCloud-Web SPA that authenticates against an external
// Keycloak realm. We log in at the IdP origin directly (first-class navigation,
// no cy.origin), cache the SSO session, then let the app complete a silent OIDC
// handshake on cy.visit("/"). Sender is party 1, so the IdP is idp1.docker by
// the idpN.docker convention; the value is config-driven for two-party runs.
const defaultIdpOrigin = "https://idp1.docker";
const defaultRealm = "cernbox";
const loggedInUrlRe = /\/files\/spaces\//;
const postLoginTimeoutMs = 30000;

export function cernboxIdpOrigin(): string {
  // idp_origin is a non-sensitive config value exposed via cypress.config.js
  // (same channel as proof_cell / receiver_baseUrl). Falls back to idp1.docker
  // for manual one-party runs where compose did not inject CYPRESS_idp_origin.
  const configured = Cypress.expose("idp_origin");
  return configured !== undefined &&
    configured !== null &&
    String(configured) !== ""
    ? String(configured)
    : defaultIdpOrigin;
}

export function cernboxRealm(): string {
  // idp_realm comes from the platforms.nuon login SSOT via CYPRESS_idp_realm.
  // Falls back to "cernbox" for manual runs without compose injection.
  const configured = Cypress.expose("idp_realm");
  return configured !== undefined &&
    configured !== null &&
    String(configured) !== ""
    ? String(configured)
    : defaultRealm;
}

export function establishCernboxIdpSession(
  credentials: ActorCredentials,
  scenarioId?: string,
): void {
  establishIdpSession({
    idpOrigin: cernboxIdpOrigin(),
    realm: cernboxRealm(),
    credentials,
    scenarioId,
  });
}

export function completeCernboxAppLogin(): void {
  cy.intercept("GET", "**/web-oidc-callback**").as("oidcCallback");

  // The SSO session is already established; visiting the app triggers a silent
  // OIDC redirect through Keycloak that resolves back to the app origin.
  cy.visit("/");
  cy.wait("@oidcCallback", { timeout: postLoginTimeoutMs }).then(
    (interception) => {
      expect(interception.response, "OIDC callback response").to.exist;
      expect(interception.response?.statusCode, "OIDC callback status").to.eq(
        200,
      );
    },
  );
}

export function assertCernboxLoggedIn(): void {
  cy.url({ timeout: postLoginTimeoutMs }).should("match", loggedInUrlRe);
  cy.get("#web-content", { timeout: postLoginTimeoutMs }).should("be.visible");
}
