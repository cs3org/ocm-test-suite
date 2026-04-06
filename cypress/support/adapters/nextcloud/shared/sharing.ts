/// <reference types="cypress" />

import { escapeRegExp } from "../../../shared/text";
import { parseRemoteHostFromFederatedRecipientId } from "../../../shared/urls";
import {
  ensureFileExists,
  ensureFilesAppLoadedForShareAcceptance,
  getFileRow,
} from "./files";

export function openSharingPanel(sharedFileName: string): void {
  getFileRow(sharedFileName).within(() => {
    cy.get(
      '[data-cy-files-list-row-action="sharing-status"] button, button[aria-label="Sharing options"]',
      { timeout: 20000 },
    )
      .first()
      .should("be.visible")
      .click();
  });

  // External shares combobox exists within the sharing panel.
  cy.get('.sharing-search__input input[role="combobox"]', { timeout: 20000 }).should(
    "be.visible",
  );
}

function getExternalShareCombobox(): Cypress.Chainable<JQuery<HTMLInputElement>> {
  return cy
    .contains("h4, h3, h2, legend, label", /^External shares$/, { timeout: 20000 })
    .scrollIntoView()
    .should("be.visible")
    .then(($heading) => {
      const $section = $heading.closest("section");
      if ($section.length > 0) {
        return $section;
      }

      const $closestAncestorWithCombobox = $heading
        .parents()
        .filter((_, el) => {
          return Cypress.$(el).find('.sharing-search__input input[role="combobox"]').length > 0;
        })
        .first();

      if ($closestAncestorWithCombobox.length > 0) {
        return $closestAncestorWithCombobox;
      }

      return $heading.parent();
    })
    .within(() => {
      cy.get('.sharing-search__input input[role="combobox"]', { timeout: 20000 })
        .scrollIntoView()
        .should("be.visible")
        .as("externalShareCombobox");
    })
    .then(() => {
      return cy.get("@externalShareCombobox") as Cypress.Chainable<JQuery<HTMLInputElement>>;
    });
}

export function addExternalShare(federatedRecipientId: string): void {
  const remoteHost = parseRemoteHostFromFederatedRecipientId(federatedRecipientId);

  getExternalShareCombobox().clear().type(federatedRecipientId);

  cy.contains(
    '[role="option"], ul[role="listbox"] li, [role="listbox"] [role="option"]',
    new RegExp(`on\\s+${escapeRegExp(remoteHost)}`),
    { timeout: 20000 },
  )
    .should("be.visible")
    .click();

  cy.contains("h1", new RegExp(`on remote server\\s+${escapeRegExp(remoteHost)}`), {
    timeout: 20000,
  }).should("be.visible");

  cy.intercept("POST", "**/ocs/v2.php/apps/files_sharing/api/v1/shares**").as(
    "ocsShareCreate",
  );

  cy.contains("button", "Save share", { timeout: 20000 })
    .should("be.visible")
    .click();

  cy.wait("@ocsShareCreate", { timeout: 20000 }).then((interception) => {
    const statusCode = interception.response?.statusCode;
    expect(statusCode, "OCS share create status code").to.be.oneOf([200, 201]);
  });

  cy.contains('[role="alert"], .toast, .toastify', "Share saved", { timeout: 20000 })
    .should("be.visible");
}

export function handleShareAcceptance(
  sharedFileName: string,
  options: { remainingAttempts: number },
): void {
  cy.get("body").then(($body) => {
    const hasRemoteShareDialogButton =
      $body.find('button:contains("Add remote share")').filter(":visible").length > 0;

    if (hasRemoteShareDialogButton) {
      if (options.remainingAttempts <= 0) {
        throw new Error("Remote share dialog kept appearing after retries");
      }

      cy.contains("button", "Add remote share", { timeout: 20000 })
        .should("be.visible")
        .click();

      cy.reload();
      ensureFilesAppLoadedForShareAcceptance();
      handleShareAcceptance(sharedFileName, {
        remainingAttempts: options.remainingAttempts - 1,
      });
      return;
    }

    ensureFileExists(sharedFileName);
  });
}
