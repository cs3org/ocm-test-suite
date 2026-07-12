/// <reference types="cypress" />

import type { WebappShareFlowSenderAdapter } from "../../../contracts/webapp-share";
import type { NextcloudWebappShareVersion } from "./webapp-share-adapters";
import {
  ensureFileExists,
  ensureFilesAppActive,
  getFileRow,
} from "./files";

const notebookFixturePath = "webapp-share/minimal.ipynb";
const notebookUploadName = "notebook.ipynb";

// Each WebDAV path segment is URL-encoded.
function davFilesUrl(username: string, ...segments: string[]): string {
  const base = `/remote.php/dav/files/${encodeURIComponent(username)}`;
  const suffix = segments.map((segment) => encodeURIComponent(segment)).join("/");
  return suffix.length > 0 ? `${base}/${suffix}` : base;
}

// Cookie-authenticated DAV writes require the CSRF requesttoken header.
function fetchRequestToken(): Cypress.Chainable<string> {
  return cy.request("/csrftoken").then((response) => {
    const token = (response.body as { token?: string }).token;
    expect(token, "Nextcloud CSRF request token").to.be.a("string").and.not.be
      .empty;
    return token as string;
  });
}

// MKCOL: 201 created or 405 already-exists.
function provisionShareFolder(
  username: string,
  requestToken: string,
  folderName: string,
): void {
  cy.request({
    method: "MKCOL",
    url: davFilesUrl(username, folderName),
    headers: { requesttoken: requestToken },
    failOnStatusCode: false,
  }).then((response) => {
    expect(response.status, `MKCOL ${folderName}`).to.be.oneOf([201, 405]);
  });
}

// Non-empty notebook fixture via WebDAV PUT.
function provisionNotebook(
  username: string,
  requestToken: string,
  folderName: string,
): void {
  cy.fixture(notebookFixturePath).then((notebookContent) => {
    const body =
      typeof notebookContent === "string"
        ? notebookContent
        : JSON.stringify(notebookContent);

    cy.request({
      method: "PUT",
      url: davFilesUrl(username, folderName, notebookUploadName),
      headers: {
        requesttoken: requestToken,
        "Content-Type": "application/json",
      },
      body,
      failOnStatusCode: false,
    }).then((response) => {
      expect(response.status, `PUT ${notebookUploadName}`).to.be.oneOf([201, 204]);
    });
  });
}

function openShareDialogFromFileRow(folderName: string): void {
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

  // Share button is in the NcDialog actions footer, not inside .webapp-share-dialog.
  cy.get(".webapp-share-dialog", { timeout: 20000 })
    .parents('[role="dialog"]')
    .first()
    .contains("button", /^\s*Share\s*$/i)
    .should("be.visible")
    .and("not.be.disabled")
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
  version: NextcloudWebappShareVersion,
): WebappShareFlowSenderAdapter {
  const key = `nextcloud/${version}`;

  return {
    key,

    prepareShareFolder({ sharedFolderName, credentials }) {
      fetchRequestToken().then((requestToken) => {
        provisionShareFolder(credentials.username, requestToken, sharedFolderName);
        provisionNotebook(credentials.username, requestToken, sharedFolderName);
      });
      ensureFilesAppActive();
      ensureFileExists(sharedFolderName);
    },

    openWebappShareDialog({ sharedFolderName }) {
      ensureFilesAppActive();
      ensureFileExists(sharedFolderName);
      openShareDialogFromFileRow(sharedFolderName);
    },

    submitWebappShare({ federatedRecipientId }) {
      cy.get(".webapp-share-dialog input", { timeout: 20000 })
        .filter(":visible")
        .first()
        .clear()
        .type(federatedRecipientId);
      submitWebappShareDialog();
    },
  };
}
