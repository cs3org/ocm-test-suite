/// <reference types="cypress" />

import type { WebappShareFlowSenderAdapter } from "../../../contracts/webapp-share";
import { resolveCypressDownloadPath } from "../../../shared/downloads";
import {
  ensureFileExists,
  ensureFilesAppActive,
  getFileRow,
} from "./files";

const notebookFixturePath = "webapp-share/minimal.ipynb";
const notebookUploadName = "notebook.ipynb";

function openNewMenu(): void {
  const menuButtonSelectors = [
    '[data-cy-upload-picker-menu-button]',
    'button[aria-label="New"]',
    'button[aria-label*="Add"]',
    ".files-controls button.new",
  ];

  cy.get("body").then(($body) => {
    const selector = menuButtonSelectors.find((candidate) => {
      return $body.find(candidate).filter(":visible").length > 0;
    });

    if (!selector) {
      throw new Error(
        [
          "Could not find the Nextcloud Files New menu button.",
          `Tried selectors: ${menuButtonSelectors.join(", ")}`,
        ].join(" "),
      );
    }

    cy.get(selector, { timeout: 20000 }).filter(":visible").first().click();
  });
}

function createFolder(folderName: string): void {
  openNewMenu();

  cy.contains('[role="menuitem"], li, button', /New folder/i, { timeout: 20000 })
    .should("be.visible")
    .click();

  cy.intercept("MKCOL", "**/remote.php/dav/files/**").as("nextcloudMkcol");

  cy.get(
    'form[aria-label*="folder" i] input, .modal-container input[type="text"], input.input-field__input',
    { timeout: 20000 },
  )
    .filter(":visible")
    .first()
    .clear()
    .type(folderName)
    .type("{enter}");

  cy.wait("@nextcloudMkcol", { timeout: 20000 });
  ensureFileExists(folderName);
}

function openFolder(folderName: string): void {
  getFileRow(folderName).within(() => {
    cy.get("[data-cy-files-list-row-name-link]", { timeout: 20000 })
      .first()
      .should("be.visible")
      .click({ force: true });
  });

  cy.location("pathname", { timeout: 20000 }).should("include", "/apps/files");
}

function uploadNotebookIntoCurrentFolder(): void {
  cy.fixture(notebookFixturePath).then((notebookContent) => {
    const uploadPath = resolveCypressDownloadPath(notebookUploadName);
    cy.writeFile(uploadPath, notebookContent, { log: false });

    openNewMenu();
    cy.contains('[role="menuitem"], li, button', /Upload file/i, {
      timeout: 20000,
    })
      .should("be.visible")
      .click();

    cy.intercept("PUT", "**/remote.php/dav/files/**").as("nextcloudPutNotebook");
    cy.get('input[type="file"]', { timeout: 20000 })
      .first()
      .selectFile(uploadPath, { force: true });

    cy.wait("@nextcloudPutNotebook", { timeout: 20000 });
    ensureFileExists(notebookUploadName);
  });
}

function openWebappShareDialog(folderName: string): void {
  getFileRow(folderName).within(() => {
    cy.get('button[aria-label="Actions"]', { timeout: 20000 })
      .should("be.visible")
      .click();
  });

  cy.contains(
    'button, [role="menuitem"], span, li',
    /Share as JupyterHub webapp/i,
    { timeout: 20000 },
  )
    .should("be.visible")
    .click({ force: true });

  cy.get(".webapp-share-dialog", { timeout: 20000 }).should("be.visible");
}

function submitWebappShareDialog(): void {
  cy.intercept("POST", "**/apps/integration_jupyterhub/api/v1/webapp-share").as(
    "nextcloudWebappShare",
  );

  cy.contains(".webapp-share-dialog button", /^Share$/i, { timeout: 20000 })
    .should("be.visible")
    .click();

  cy.wait("@nextcloudWebappShare", { timeout: 60000 }).then((interception) => {
    const statusCode = interception.response?.statusCode;
    expect(statusCode, "Nextcloud webapp-share API status code").to.be.oneOf([200, 201]);
  });

  cy.contains('[role="alert"], .toast, .toastify', /Shared .+ with /i, {
    timeout: 20000,
  }).should("be.visible");
}

export function createNextcloudWebappShareSenderAdapter(
  version: "v35",
): WebappShareFlowSenderAdapter {
  const key = `nextcloud/${version}`;

  return {
    key,

    prepareShareFolder({ sharedFolderName }) {
      ensureFilesAppActive();
      createFolder(sharedFolderName);
      openFolder(sharedFolderName);
      uploadNotebookIntoCurrentFolder();
      ensureFilesAppActive();
      ensureFileExists(sharedFolderName);
    },

    openWebappShareDialog({ sharedFolderName }) {
      ensureFilesAppActive();
      ensureFileExists(sharedFolderName);
      openWebappShareDialog(sharedFolderName);
    },

    submitWebappShare({ federatedRecipientId }) {
      cy.get(".webapp-share-dialog input", { timeout: 20000 })
        .filter(":visible")
        .first()
        .clear()
        .type(federatedRecipientId);
      submitWebappShareDialog();
    },

    shareWebappWithFederatedRecipient({ sharedFolderName, federatedRecipientId }) {
      ensureFilesAppActive();
      ensureFileExists(sharedFolderName);
      openWebappShareDialog(sharedFolderName);

      cy.get(".webapp-share-dialog input", { timeout: 20000 })
        .filter(":visible")
        .first()
        .clear()
        .type(federatedRecipientId);

      submitWebappShareDialog();
    },
  };
}
