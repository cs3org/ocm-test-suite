/// <reference types="cypress" />

import type { ActorCredentials } from "../../../contracts/login";

const loggedInUrlRe =
  /(?:files\/spaces\/personal|f\/[0-9a-f-]+|files)(?:\/|$|[?#])/;
const postLoginTimeoutMs = 10000;

export function openOpenCloudLoginPage(): void {
  cy.visit("/");

  cy.get("form.oc-login-form", { timeout: postLoginTimeoutMs }).should(
    "be.visible",
  );
  cy.get("input#oc-login-username").should("be.visible");
  cy.get("input#oc-login-password").should("be.visible");
}

export function submitOpenCloudLoginForm(credentials: ActorCredentials): void {
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

  assertOpenCloudLoggedIn();

  cy.get("#web-content", { timeout: postLoginTimeoutMs }).should("be.visible");
}

export function loginOpenCloudViaUi(credentials: ActorCredentials): void {
  openOpenCloudLoginPage();
  submitOpenCloudLoginForm(credentials);
}

export function assertOpenCloudLoggedIn(): void {
  cy.url({ timeout: postLoginTimeoutMs }).should("match", loggedInUrlRe);
}
