/// <reference types="cypress" />

import type { LoginAdapter } from "../../../contracts/login";

export const ocmgoV1LoginAdapter: LoginAdapter = {
  key: "ocmgo/v1",

  login(credentials) {
    cy.visit("/ui/login");

    cy.get("#username", { timeout: 20000 }).clear().type(credentials.username);
    cy.get("#password", { timeout: 20000 })
      .clear()
      .type(credentials.password, { log: false });
    cy.get("#submit-btn", { timeout: 20000 }).click();

    cy.url({ timeout: 20000 }).should("include", "/ui/inbox");
  },

  assertLoggedIn() {
    cy.url({ timeout: 20000 }).should("include", "/ui/inbox");
  },
};

