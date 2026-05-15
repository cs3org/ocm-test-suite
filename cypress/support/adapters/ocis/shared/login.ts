/// <reference types="cypress" />

import type { ActorCredentials } from "../../../contracts/login";

const loggedInUrlRe = /files\/spaces\/personal(\/|$)/;
const postLoginTimeoutMs = 10000;

export function openOcisLoginPage(): void {
  cy.visit("/");

  cy.get("form.oc-login-form", { timeout: postLoginTimeoutMs }).should(
    "be.visible",
  );
  cy.get("input#oc-login-username").should("be.visible");
  cy.get("input#oc-login-password").should("be.visible");
}

export function submitOcisLoginForm(credentials: ActorCredentials): void {
  cy.intercept("POST", "**/token").as("loginToken");

  cy.get("form.oc-login-form").within(() => {
    cy.get("input#oc-login-username").type(credentials.username);
    cy.get("input#oc-login-password").type(credentials.password, {
      log: false,
    });
    cy.get('button[type="submit"]').click();
  });

  cy.wait("@loginToken", { timeout: postLoginTimeoutMs }).then(
    (interception) => {
      expect(interception.response, "login token response").to.exist;
      expect(interception.response?.statusCode, "login token status").to.eq(
        200,
      );
    },
  );

  assertOcisLoggedIn();

  cy.get("#web-content", { timeout: postLoginTimeoutMs }).should("be.visible");
}

export function loginOcisViaUi(credentials: ActorCredentials): void {
  openOcisLoginPage();
  submitOcisLoginForm(credentials);
}

export function assertOcisLoggedIn(): void {
  cy.url({ timeout: postLoginTimeoutMs }).should("match", loggedInUrlRe);
}
