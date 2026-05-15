/// <reference types="cypress" />

import type { LoginAdapter } from "../../../contracts/login";

export const ocmgoV1LoginAdapter: LoginAdapter = {
  key: "ocmgo/v1",

  openLoginPage() {
    cy.visit("/ui/login");
    cy.get("#username", { timeout: 20000 }).should("be.visible");
    cy.get("#password", { timeout: 20000 }).should("be.visible");
  },

  submitLogin(credentials) {
    cy.get("#username", { timeout: 20000 }).clear().type(credentials.username);
    cy.get("#password", { timeout: 20000 })
      .clear()
      .type(credentials.password, { log: false });
    cy.get("#submit-btn", { timeout: 20000 }).click();

    cy.url({ timeout: 20000 }).should("include", "/ui/inbox");
  },

  login(credentials) {
    this.openLoginPage();
    this.submitLogin(credentials);
  },

  assertLoggedIn() {
    cy.url({ timeout: 20000 }).should("include", "/ui/inbox");
  },
};
