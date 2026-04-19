/// <reference types="cypress" />

// oCIS files-app helpers.

import { cssEscapeAttributeValue } from "../../../shared/selectors";
import { resolveCypressDownloadPath } from "../../../shared/downloads";
import type { OcisProfile } from "./profile";

const filesAppTimeoutMs = 20000;
const editorTimeoutMs = 20000;
const contextMenuTimeoutMs = 20000;
const contentReadTimeoutMs = 30000;

export interface OcisFilesHelpers {
  ensureFilesAppActive: () => void;
  ensureFileExists: (fileName: string) => void;
  assertFileContent: (fileName: string, expectedContent: string) => void;
  createTextFile: (fileName: string, content: string) => void;
}

export function makeOcisFilesHelpers(profile: OcisProfile): OcisFilesHelpers {
  const sel = profile.selectors.files;
  const net = profile.network;

  function ensureFilesAppActive(): void {
    cy.viewport(1280, 720);
    cy.visit("/");
    cy.get(sel.webContent, { timeout: filesAppTimeoutMs }).should("be.visible");

    cy.get("body").then(($body) => {
      const alreadyInFiles =
        $body.find(sel.filesViewSentinels).length > 0 ||
        window.location.href.includes("files");
      if (alreadyInFiles) {
        return;
      }
      cy.get(sel.appSwitcherButton, { timeout: filesAppTimeoutMs })
        .should("be.visible")
        .click({ force: true });

      cy.get(sel.filesAppMenuItem, { timeout: filesAppTimeoutMs })
        .should("be.visible")
        .click({ force: true });
    });

    // Confirm the files view container is mounted. Present whether the space
    // is empty (empty-state rendered) or populated (resource rows rendered).
    cy.get(sel.filesView, { timeout: filesAppTimeoutMs }).should("exist");
  }

  function ensureFileExists(fileName: string): void {
    const escapedName = cssEscapeAttributeValue(fileName);
    cy.get(sel.resourceByName(escapedName), { timeout: filesAppTimeoutMs })
      .first()
      .scrollIntoView()
      .should("be.visible");
  }

  // Proves file content by downloading via the topbar context menu rather than
  // reading the editor DOM. This avoids the read-only vs writable textbox
  // selector divergence on OCM-received shares.
  //
  // Flow: single-click the resource row to open the viewer route, wait for the
  // topbar trigger to mount, open the context menu, then click the download action.
  function assertFileContent(
    fileName: string,
    expectedContent: string,
  ): void {
    const escapedName = cssEscapeAttributeValue(fileName);

    // Remove a stale download from any previous run so cy.readFile cannot
    // pick up old content.
    cy.exec(`rm -f "${resolveCypressDownloadPath(fileName)}"`, {
      failOnNonZeroExit: false,
    });

    cy.get(sel.resourceByName(escapedName), { timeout: contentReadTimeoutMs })
      .first()
      .scrollIntoView()
      .should("be.visible")
      .click({ force: true });

    cy.get(sel.openFileContextMenuTrigger, { timeout: contextMenuTimeoutMs })
      .should("be.visible")
      .click({ force: true });

    cy.get(sel.openFileContextDownloadAction, { timeout: contextMenuTimeoutMs })
      .should("be.visible")
      .click({ force: true });

    cy.readFile(resolveCypressDownloadPath(fileName), { timeout: 30000 }).then(
      (content: string) => {
        expect(content.trim()).to.equal(expectedContent.trim());
      },
    );
  }

  function createTextFile(fileName: string, content: string): void {
    // Gate file creation and save on WebDAV PUT responses so UI transitions
    // never race the server. The /text-editor/ route is pushed only after
    // the creation PUT resolves.
    cy.intercept("PUT", net.webdavSpacesGlob).as("ocisPutFile");
    cy.intercept("PROPFIND", net.webdavSpacesGlob).as("ocisPropfindSpace");

    cy.get(sel.newFileMenuButton, { timeout: filesAppTimeoutMs })
      .should("be.visible")
      .should("be.enabled")
      .click();

    cy.get(sel.newFileMenuDrop, { timeout: filesAppTimeoutMs }).should(
      "be.visible",
    );

    // sel.newTextFileMenuItem is the locale-independent class hook on the
    // plain-text action button.
    cy.get(sel.newTextFileMenuItem, { timeout: filesAppTimeoutMs })
      .should("be.visible")
      .should("be.enabled")
      .click();

    // The modal pre-fills a default name; clear it before typing the target name.
    cy.get(sel.modalInput, { timeout: filesAppTimeoutMs })
      .should("be.visible")
      .clear()
      .type(fileName)
      .should("have.value", fileName);

    cy.get(sel.modal, { timeout: filesAppTimeoutMs })
      .find(sel.modalConfirm)
      .should("be.visible")
      .should("be.enabled")
      .click();

    cy.wait("@ocisPutFile", { timeout: editorTimeoutMs })
      .its("response.statusCode")
      .should("eq", net.webdavPutCreateStatus);

    cy.location("pathname", { timeout: editorTimeoutMs }).should(
      "include",
      sel.editorRouteFragment,
    );

    cy.get(sel.editorWrapper, { timeout: editorTimeoutMs }).should("be.visible");

    // The editor content selector is profile-driven: v12.3.2 uses
    // md-editor-v3 + CodeMirror 6 (`#text-editor-container .cm-content`).
    cy.get(sel.editorContent, { timeout: editorTimeoutMs })
      .should("be.visible")
      .click()
      .type(content);

    cy.get(sel.saveButton, { timeout: editorTimeoutMs })
      .should("be.visible")
      .should("be.enabled")
      .click();

    cy.wait("@ocisPutFile", { timeout: editorTimeoutMs })
      .its("response.statusCode")
      .should("eq", net.webdavPutSaveStatus);

    // The text-editor save triggers a PROPFIND on the parent space immediately
    // after the content PUT; waiting here ensures the server has indexed the
    // new file before ensureFilesAppActive() navigates back to the list.
    cy.wait("@ocisPropfindSpace", { timeout: editorTimeoutMs })
      .its("response.statusCode")
      .should("eq", net.webdavPropfindStatus);

    // The save is server-confirmed by the PUT and PROPFIND waits above.
    // Return to the files view so the resource list reflects server state.
    ensureFilesAppActive();

    const escaped = cssEscapeAttributeValue(fileName);
    cy.get(sel.resourceByName(escaped), { timeout: filesAppTimeoutMs }).should(
      "be.visible",
    );
  }

  return { ensureFilesAppActive, ensureFileExists, assertFileContent, createTextFile };
}
