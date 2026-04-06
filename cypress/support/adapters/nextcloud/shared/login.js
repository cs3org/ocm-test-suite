"use strict";
/// <reference types="cypress" />
Object.defineProperty(exports, "__esModule", { value: true });
exports.loginNextcloudViaUi = loginNextcloudViaUi;
exports.submitNextcloudLoginForm = submitNextcloudLoginForm;
exports.assertNextcloudLoggedIn = assertNextcloudLoggedIn;
function loginNextcloudViaUi(_a) {
    var username = _a.username, password = _a.password;
    cy.intercept("POST", "**/login*").as("nextcloudLogin");
    submitNextcloudLoginForm({ username: username, password: password });
    cy.wait("@nextcloudLogin", { timeout: 20000 });
}
function submitNextcloudLoginForm(_a) {
    var username = _a.username, password = _a.password;
    cy.visit("/");
    cy.get('form[name="login"]', { timeout: 10000 })
        .should("be.visible")
        .within(function () {
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
function assertNextcloudLoggedIn() {
    cy.get('form[name="login"]').should("not.exist");
    cy.location("pathname", { timeout: 20000 }).should("not.include", "/login");
}
