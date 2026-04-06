"use strict";
/// <reference types="cypress" />
Object.defineProperty(exports, "__esModule", { value: true });
exports.ensureFilesAppActive = ensureFilesAppActive;
exports.ensureFilesAppLoadedForShareAcceptance = ensureFilesAppLoadedForShareAcceptance;
exports.getFileRow = getFileRow;
exports.ensureFileExists = ensureFileExists;
exports.renameFile = renameFile;
var selectors_1 = require("../../../shared/selectors");
var filesTableSelector = "table.files-list__table";
function filesRowSelector(fileName) {
    return "tbody.files-list__tbody [data-cy-files-list-row-name=\"".concat((0, selectors_1.cssEscapeAttributeValue)(fileName), "\"]");
}
function ensureFilesAppActive() {
    cy.visit("/");
    cy.location("pathname", { timeout: 20000 }).then(function (pathname) {
        if (typeof pathname === "string" && pathname.includes("/apps/files")) {
            return;
        }
        cy.visit("/apps/files/");
    });
    cy.get(filesTableSelector, { timeout: 20000 }).should("be.visible");
}
function ensureFilesAppLoadedForShareAcceptance() {
    cy.visit("/");
    cy.location("pathname", { timeout: 20000 }).then(function (pathname) {
        if (typeof pathname === "string" && pathname.includes("/apps/files")) {
            return;
        }
        cy.visit("/apps/files/");
    });
    cy.get(filesTableSelector, { timeout: 20000 }).should("exist");
}
function getFileRow(fileName) {
    return cy
        .get("".concat(filesTableSelector, " ").concat(filesRowSelector(fileName)), { timeout: 20000 })
        .first()
        .closest("tr")
        .should("be.visible");
}
function ensureFileExists(fileName, options) {
    if (options === void 0) { options = { remainingAttempts: 3 }; }
    cy.get(filesTableSelector, { timeout: 20000 }).should("be.visible");
    cy.get("body").then(function ($body) {
        var selector = "".concat(filesTableSelector, " ").concat(filesRowSelector(fileName));
        var isPresent = $body.find(selector).length > 0;
        if (isPresent) {
            getFileRow(fileName);
            return;
        }
        if (options.remainingAttempts <= 0) {
            throw new Error("Expected file row to exist: \"".concat(fileName, "\""));
        }
        cy.reload();
        ensureFilesAppActive();
        ensureFileExists(fileName, { remainingAttempts: options.remainingAttempts - 1 });
    });
}
function clickRenameAction() {
    var candidates = [
        '[data-cy-files-list-row-action="rename"] button',
        'button[aria-label="Rename"]',
        'button[aria-label="Rename file"]',
    ];
    cy.get("body").then(function ($body) {
        var selector = candidates.find(function (sel) {
            return $body.find(sel).filter(":visible").length > 0;
        });
        if (!selector) {
            throw new Error([
                "Could not find Nextcloud rename action button.",
                "Tried selectors: ".concat(candidates.join(", ")),
            ].join(" "));
        }
        cy.get(selector, { timeout: 20000 }).filter(":visible").first().click();
    });
}
function getRenameInput() {
    var candidates = [
        'form[aria-label="Rename file"] input.input-field__input',
        'form[aria-label*="Rename"] input',
    ];
    return cy.get("body").then(function ($body) {
        var selector = candidates.find(function (sel) { return $body.find(sel).length > 0; });
        if (!selector) {
            throw new Error([
                "Could not find Nextcloud rename input.",
                "Tried selectors: ".concat(candidates.join(", ")),
            ].join(" "));
        }
        return cy.get(selector, { timeout: 20000 }).first();
    });
}
function renameFile(sourceFileName, sharedFileName) {
    cy.intercept({
        method: "MOVE",
        url: "**/remote.php/dav/files/**",
    }).as("davMove");
    getFileRow(sourceFileName).within(function () {
        cy.get('button[aria-label="Actions"]', { timeout: 20000 })
            .should("be.visible")
            .click();
    });
    // Nextcloud versions differ in where the rename action is mounted (row vs global popover).
    clickRenameAction();
    getRenameInput()
        .should("be.visible")
        .clear()
        .type(sharedFileName)
        .type("{enter}");
    cy.wait("@davMove", { timeout: 20000 });
}
