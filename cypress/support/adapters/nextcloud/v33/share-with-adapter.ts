/// <reference types="cypress" />

import type { ShareWithAdapter } from "../../../contracts/share-with";

const filesTableSelector = "table.files-list__table";

function cssEscapeAttributeValue(value: string) {
  // CSS attribute values are in double quotes in our selectors.
  return value.replaceAll("\\", "\\\\").replaceAll('"', '\\"');
}

function filesRowSelector(fileName: string) {
  return `tbody.files-list__tbody [data-cy-files-list-row-name="${cssEscapeAttributeValue(fileName)}"]`;
}

export const nextcloudV33ShareWithAdapter: ShareWithAdapter = {
  key: "nextcloud/v33",

  prepareShareFile({ sourceFileName = "welcome.txt", sharedFileName }) {
    ensureFilesAppActive();

    cy.log(`prepare share file: ${sourceFileName} -> ${sharedFileName}`);

    ensureFileExists(sourceFileName);
    renameFile(sourceFileName, sharedFileName);
    ensureFileExists(sharedFileName);
  },

  shareWithFederatedRecipient({ sharedFileName, federatedRecipientId }) {
    ensureFilesAppActive();

    cy.log(`share ${sharedFileName} -> ${federatedRecipientId}`);

    openSharingPanel(sharedFileName);
    addExternalShare(federatedRecipientId);
  },

  acceptIncomingShare({ sharedFileName }) {
    ensureFilesAppLoadedForShareAcceptance();

    handleShareAcceptance(sharedFileName, { remainingAttempts: 3 });
  },
};

function ensureFilesAppActive() {
  cy.visit("/");

  cy.location("pathname", { timeout: 20000 }).then((pathname) => {
    if (typeof pathname === "string" && pathname.includes("/apps/files")) {
      return;
    }
    cy.visit("/apps/files/");
  });

  cy.get(filesTableSelector, { timeout: 20000 }).should("be.visible");
}

function ensureFilesAppLoadedForShareAcceptance() {
  cy.visit("/");

  cy.location("pathname", { timeout: 20000 }).then((pathname) => {
    if (typeof pathname === "string" && pathname.includes("/apps/files")) {
      return;
    }
    cy.visit("/apps/files/");
  });

  cy.get(filesTableSelector, { timeout: 20000 }).should("exist");
}

function getFileRow(fileName: string): Cypress.Chainable<JQuery<HTMLElement>> {
  return cy
    .get(`${filesTableSelector} ${filesRowSelector(fileName)}`, { timeout: 20000 })
    .first()
    .closest("tr")
    .should("be.visible");
}

function ensureFileExists(
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

function renameFile(sourceFileName: string, sharedFileName: string): void {
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

function openSharingPanel(sharedFileName: string): void {
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
  cy.get(".sharing-search__input input[role=\"combobox\"]", { timeout: 20000 }).should(
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

function addExternalShare(federatedRecipientId: string): void {
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

function handleShareAcceptance(
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

function parseRemoteHostFromFederatedRecipientId(federatedRecipientId: string): string {
  const afterAt = federatedRecipientId.split("@").at(-1) ?? federatedRecipientId;
  const withoutProtocol = afterAt.replace(/^https?:\/\//, "");
  const hostAndMaybePath = withoutProtocol.split("/")[0] ?? withoutProtocol;
  return hostAndMaybePath.trim();
}

function escapeRegExp(value: string): string {
  return value.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

