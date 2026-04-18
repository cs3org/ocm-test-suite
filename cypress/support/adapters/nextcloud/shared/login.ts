/// <reference types="cypress" />

import type { ActorCredentials } from "../../../contracts/login";

export function loginNextcloudViaUi({ username, password }: ActorCredentials) {
  cy.intercept("POST", "**/login*").as("nextcloudLogin");

  openNextcloudLoginPage();
  submitNextcloudLoginForm({ username, password });
  cy.wait("@nextcloudLogin", { timeout: 20000 });
}

export function openNextcloudLoginPage() {
  cy.visit("/");
  cy.get('form[name="login"]', { timeout: 10000 }).should("be.visible");
  cy.get('input[name="user"]').should("be.visible");
  cy.get('input[name="password"]').should("be.visible");
}

export function submitNextcloudLoginForm({
  username,
  password,
}: ActorCredentials) {
  cy.get('form[name="login"]', { timeout: 10000 })
    .should("be.visible")
    .within(() => {
      cy.get('input[name="user"]').should("be.visible").clear().type(username);
      cy.get('input[name="password"]')
        .should("be.visible")
        .clear()
        .type(password, { log: false });

      cy.contains("button[data-login-form-submit]", "Log in")
        .should("be.visible")
        .click();
    });
}

export function assertNextcloudLoggedIn() {
  cy.get('form[name="login"]').should("not.exist");
  cy.location("pathname", { timeout: 20000 }).should("not.include", "/login");
}
