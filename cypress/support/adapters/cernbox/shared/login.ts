/// <reference types="cypress" />

import type { ActorCredentials } from "../../../contracts/login";

// CERNBox web is an ownCloud-Web SPA that authenticates against an external
// Keycloak realm on a separate origin. Visiting the app root redirects the
// browser to the IdP, so every IdP-side DOM action runs inside cy.origin();
// app-side assertions run on the primary origin after the OIDC callback returns.
const idpOrigin = "https://idp.docker";
const loggedInUrlRe = /\/files\/spaces\//;
const idpFormTimeoutMs = 30000;
const postLoginTimeoutMs = 30000;

export function openCernboxLoginPage(): void {
  cy.visit("/");

  // App auto-redirects to the Keycloak realm. Wait for the IdP form on its own
  // origin and leave it on screen for the login-page-ready evidence screenshot.
  cy.origin(
    idpOrigin,
    { args: { idpFormTimeoutMs } },
    ({ idpFormTimeoutMs }) => {
      cy.get("form#kc-form-login", { timeout: idpFormTimeoutMs }).should(
        "be.visible",
      );
    },
  );
}

export function submitCernboxLoginForm(credentials: ActorCredentials): void {
  const { username, password } = credentials;

  // Register the callback spy on the primary origin before leaving for the IdP.
  // Intercepts are network-level and fire regardless of the active origin.
  cy.intercept("GET", "**/web-oidc-callback**").as("oidcCallback");

  cy.origin(
    idpOrigin,
    { args: { username, password, idpFormTimeoutMs } },
    ({ username, password, idpFormTimeoutMs }) => {
      // Selectors pinned to Keycloak 26.4.2 keycloak.v2 theme (idp:v26.4.2);
      // no name= fallbacks so theme drift fails fast instead of silently.
      cy.get("form#kc-form-login", { timeout: idpFormTimeoutMs })
        .should("be.visible")
        .within(() => {
          cy.get("input#username").clear().type(username);
          cy.get("input#password").clear().type(password, { log: false });
          cy.get("button#kc-login").should("be.enabled").click();
        });
    },
  );

  // The IdP redirects back to the app's OIDC callback (same origin as baseUrl).
  // Assert the callback actually loaded so auth/network failures surface here,
  // matching the response checks in the ocis/opencloud submit helpers.
  cy.wait("@oidcCallback", { timeout: postLoginTimeoutMs }).then(
    (interception) => {
      expect(interception.response, "OIDC callback response").to.exist;
      expect(interception.response?.statusCode, "OIDC callback status").to.eq(
        200,
      );
    },
  );
}

export function loginCernboxViaUi(credentials: ActorCredentials): void {
  openCernboxLoginPage();
  submitCernboxLoginForm(credentials);
  assertCernboxLoggedIn();
}

export function assertCernboxLoggedIn(): void {
  cy.url({ timeout: postLoginTimeoutMs }).should("match", loggedInUrlRe);
  cy.get("#web-content", { timeout: postLoginTimeoutMs }).should("be.visible");
}
