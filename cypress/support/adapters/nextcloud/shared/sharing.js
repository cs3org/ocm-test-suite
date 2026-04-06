"use strict";
/// <reference types="cypress" />
Object.defineProperty(exports, "__esModule", { value: true });
exports.openSharingPanel = openSharingPanel;
exports.addExternalShare = addExternalShare;
exports.handleShareAcceptance = handleShareAcceptance;
var text_1 = require("../../../shared/text");
var urls_1 = require("../../../shared/urls");
var files_1 = require("./files");
function openSharingPanel(sharedFileName) {
    (0, files_1.getFileRow)(sharedFileName).within(function () {
        cy.get('[data-cy-files-list-row-action="sharing-status"] button, button[aria-label="Sharing options"]', { timeout: 20000 })
            .first()
            .should("be.visible")
            .click();
    });
    // External shares combobox exists within the sharing panel.
    cy.get('.sharing-search__input input[role="combobox"]', { timeout: 20000 }).should("be.visible");
}
function getExternalShareCombobox() {
    return cy
        .contains("h4, h3, h2, legend, label", /^External shares$/, { timeout: 20000 })
        .scrollIntoView()
        .should("be.visible")
        .then(function ($heading) {
        var $section = $heading.closest("section");
        if ($section.length > 0) {
            return $section;
        }
        var $closestAncestorWithCombobox = $heading
            .parents()
            .filter(function (_, el) {
            return Cypress.$(el).find('.sharing-search__input input[role="combobox"]').length > 0;
        })
            .first();
        if ($closestAncestorWithCombobox.length > 0) {
            return $closestAncestorWithCombobox;
        }
        return $heading.parent();
    })
        .within(function () {
        cy.get('.sharing-search__input input[role="combobox"]', { timeout: 20000 })
            .scrollIntoView()
            .should("be.visible")
            .as("externalShareCombobox");
    })
        .then(function () {
        return cy.get("@externalShareCombobox");
    });
}
function addExternalShare(federatedRecipientId) {
    var remoteHost = (0, urls_1.parseRemoteHostFromFederatedRecipientId)(federatedRecipientId);
    getExternalShareCombobox().clear().type(federatedRecipientId);
    cy.contains('[role="option"], ul[role="listbox"] li, [role="listbox"] [role="option"]', new RegExp("on\\s+".concat((0, text_1.escapeRegExp)(remoteHost))), { timeout: 20000 })
        .should("be.visible")
        .click();
    cy.contains("h1", new RegExp("on remote server\\s+".concat((0, text_1.escapeRegExp)(remoteHost))), {
        timeout: 20000,
    }).should("be.visible");
    cy.intercept("POST", "**/ocs/v2.php/apps/files_sharing/api/v1/shares**").as("ocsShareCreate");
    cy.contains("button", "Save share", { timeout: 20000 })
        .should("be.visible")
        .click();
    cy.wait("@ocsShareCreate", { timeout: 20000 }).then(function (interception) {
        var _a;
        var statusCode = (_a = interception.response) === null || _a === void 0 ? void 0 : _a.statusCode;
        expect(statusCode, "OCS share create status code").to.be.oneOf([200, 201]);
    });
    cy.contains('[role="alert"], .toast, .toastify', "Share saved", { timeout: 20000 })
        .should("be.visible");
}
function handleShareAcceptance(sharedFileName, options) {
    cy.get("body").then(function ($body) {
        var hasRemoteShareDialogButton = $body.find('button:contains("Add remote share")').filter(":visible").length > 0;
        if (hasRemoteShareDialogButton) {
            if (options.remainingAttempts <= 0) {
                throw new Error("Remote share dialog kept appearing after retries");
            }
            cy.contains("button", "Add remote share", { timeout: 20000 })
                .should("be.visible")
                .click();
            cy.reload();
            (0, files_1.ensureFilesAppLoadedForShareAcceptance)();
            handleShareAcceptance(sharedFileName, {
                remainingAttempts: options.remainingAttempts - 1,
            });
            return;
        }
        (0, files_1.ensureFileExists)(sharedFileName);
    });
}
