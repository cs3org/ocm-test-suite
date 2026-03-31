/// <reference types="cypress" />

import { cssEscapeAttributeValue } from "../../../shared/selectors";

const filesTableSelector = "table.files-list__table";

function filesRowSelector(fileName: string) {
  return `tbody.files-list__tbody [data-cy-files-list-row-name="${cssEscapeAttributeValue(fileName)}"]`;
}

export function ensureFilesAppActive() {
  cy.visit("/");

  cy.location("pathname", { timeout: 20000 }).then((pathname) => {
    if (typeof pathname === "string" && pathname.includes("/apps/files")) {
      return;
    }
    cy.visit("/apps/files/");
  });

  cy.get(filesTableSelector, { timeout: 20000 }).should("be.visible");
}

export function ensureFilesAppLoadedForShareAcceptance() {
  cy.visit("/");

  cy.location("pathname", { timeout: 20000 }).then((pathname) => {
    if (typeof pathname === "string" && pathname.includes("/apps/files")) {
      return;
    }
    cy.visit("/apps/files/");
  });

  cy.get(filesTableSelector, { timeout: 20000 }).should("exist");
}

export function getFileRow(fileName: string): Cypress.Chainable<JQuery<HTMLElement>> {
  return cy
    .get(`${filesTableSelector} ${filesRowSelector(fileName)}`, { timeout: 20000 })
    .first()
    .closest("tr")
    .should("be.visible");
}

export function ensureFileExists(
  fileName: string,
  options: { remainingAttempts: number } = { remainingAttempts: 3 },
): void {
  cy.get(filesTableSelector, { timeout: 20000 }).should("be.visible");

  cy.get("body").then(($body) => {
    const selector = `${filesTableSelector} ${filesRowSelector(fileName)}`;
    const isPresent = $body.find(selector).length > 0;
    if (isPresent) {
      getFileRow(fileName);
      return;
    }

    if (options.remainingAttempts <= 0) {
      throw new Error(`Expected file row to exist: "${fileName}"`);
    }

    cy.reload();
    ensureFilesAppActive();
    ensureFileExists(fileName, { remainingAttempts: options.remainingAttempts - 1 });
  });
}

export function renameFile(sourceFileName: string, sharedFileName: string): void {
  cy.intercept({
    method: "MOVE",
    url: "**/remote.php/dav/files/**",
  }).as("davMove");

  getFileRow(sourceFileName).within(() => {
    cy.get('button[aria-label="Actions"]', { timeout: 20000 })
      .should("be.visible")
      .click();
  });

  // NOTE: In Nextcloud v33 this rename action button is not within the row.
  cy.get('[data-cy-files-list-row-action="rename"] button', { timeout: 10000 })
    .should("be.visible")
    .click();

  cy.get('form[aria-label="Rename file"] input.input-field__input', {
    timeout: 20000,
  })
    .should("be.visible")
    .clear()
    .type(sharedFileName)
    .type("{enter}");

  cy.wait("@davMove", { timeout: 20000 });
}
