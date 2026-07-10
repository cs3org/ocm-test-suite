/// <reference types="cypress" />

// CERNBox files-app helpers.

import { cssEscapeAttributeValue } from "../../../shared/selectors";
import type { CernboxProfile } from "./profile";

const filesAppTimeoutMs = 20000;
const editorTimeoutMs = 20000;
const contentReadTimeoutMs = 30000;

// Pure in-tab window.open replacement for unit tests and Cypress runtime.
//
// The OCM "Open remotely" action pre-opens a named popup
// (window.open("about:blank", name)) to hold a user-gesture-tied handle, then
// form-POSTs the launch into that named target. To keep everything in the
// single Cypress-controlled tab: name the current window so a later
// form target=name resolves in-tab, and do NOT navigate on the about:blank
// preopen (that would tear down the app and abort the in-flight launch request).
export function redirectWindowOpenInSameWindow(
  win: Window,
  url: string | URL | undefined | null,
  target?: string | null,
): Window {
  if (typeof target === "string" && target.trim() !== "") {
    try {
      win.name = target;
    } catch {
      // Some runtimes forbid renaming the window; the form target then falls
      // back to a new browsing context, which the caller handles.
    }
  }

  const href = url === undefined || url === null ? "" : String(url);
  if (href !== "" && href !== "about:blank") {
    win.location.assign(href);
  }
  return win;
}

export interface CernboxFilesHelpers {
  ensureFilesAppActive: () => void;
  ensureFileExists: (fileName: string) => void;
  assertFileContent: (fileName: string, expectedContent: string) => void;
  createTextFile: (fileName: string, content: string) => void;
  stubWindowOpenForInTabNavigation: () => void;
}

export function makeCernboxFilesHelpers(
  profile: CernboxProfile,
): CernboxFilesHelpers {
  const sel = profile.selectors.files;
  const net = profile.network;

  function ensureFilesAppActive(): void {
    cy.viewport(1280, 720);
    cy.visit("/");
    cy.get(sel.webContent, { timeout: filesAppTimeoutMs }).should("be.visible");

    cy.location("href").then((href) => {
      cy.get("body").then(($body) => {
        const alreadyInFiles =
          $body.find(sel.filesViewSentinels).length > 0 ||
          href.includes("files");
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
    });

    cy.get(sel.filesView, { timeout: filesAppTimeoutMs }).should("exist");
  }

  function ensureFileExists(fileName: string): void {
    const escapedName = cssEscapeAttributeValue(fileName);
    cy.get(sel.resourceByName(escapedName), { timeout: filesAppTimeoutMs })
      .first()
      .scrollIntoView()
      .should("be.visible");
  }

  // cernFeatures opens the text editor in a new tab via window.open. Stub it
  // so navigation stays in the Cypress-controlled window for content proof.
  function stubWindowOpenForInTabNavigation(): void {
    cy.window().then((win) => {
      if (
        typeof win.open === "function" &&
        !(win.open as unknown as { isSinonProxy?: boolean }).isSinonProxy
      ) {
        cy.stub(win, "open").callsFake(
          (url?: string | URL, target?: string) =>
            redirectWindowOpenInSameWindow(win, url, target),
        );
      }
    });
  }

  function assertFileContent(
    fileName: string,
    expectedContent: string,
  ): void {
    const escapedName = cssEscapeAttributeValue(fileName);

    stubWindowOpenForInTabNavigation();

    cy.get(sel.resourceByName(escapedName), { timeout: contentReadTimeoutMs })
      .first()
      .scrollIntoView()
      .should("be.visible")
      .then(($resource) => {
        const $link = $resource.is("a") ? $resource : $resource.closest("a");
        if ($link.length > 0) {
          cy.wrap($link).invoke("removeAttr", "target").click({ force: true });
        } else {
          cy.wrap($resource).click({ force: true });
        }
      });

    cy.location("pathname", { timeout: editorTimeoutMs }).should(
      "include",
      sel.editorRouteFragment,
    );

    cy.get(sel.editorContent, { timeout: editorTimeoutMs })
      .should("be.visible")
      .then(($editor) => {
        const normalize = (v: string) =>
          String(v ?? "").replace(/\r\n/g, "\n").replace(/\n+$/, "");
        const lineNodes = $editor.find(".cm-line");
        const actual =
          lineNodes.length > 0
            ? Array.from(lineNodes, (n) => n.textContent ?? "").join("\n")
            : String($editor.text() ?? "");
        expect(normalize(actual)).to.equal(normalize(expectedContent));
      });
  }

  function createTextFile(fileName: string, content: string): void {
    stubWindowOpenForInTabNavigation();

    cy.intercept("PUT", net.webdavSpacesGlob).as("cernboxPutFile");
    cy.intercept("PROPFIND", net.webdavSpacesGlob).as("cernboxPropfindSpace");

    cy.get(sel.fab, { timeout: filesAppTimeoutMs })
      .should("be.visible")
      .should("be.enabled")
      .click();

    cy.get(sel.fabDrop, { timeout: filesAppTimeoutMs }).should("be.visible");

    cy.get(sel.newTextFileMenuItem, { timeout: filesAppTimeoutMs })
      .should("be.visible")
      .should("be.enabled")
      .click();

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

    cy.wait("@cernboxPutFile", { timeout: editorTimeoutMs })
      .its("response.statusCode")
      .should("eq", net.webdavPutCreateStatus);

    cy.location("pathname", { timeout: editorTimeoutMs }).should(
      "include",
      sel.editorRouteFragment,
    );

    cy.get(sel.editorWrapper, { timeout: editorTimeoutMs }).should("be.visible");

    cy.get(sel.editorContent, { timeout: editorTimeoutMs })
      .should("be.visible")
      .click()
      .type(content);

    cy.get(sel.saveButton, { timeout: editorTimeoutMs })
      .should("be.visible")
      .should("be.enabled")
      .click();

    cy.wait("@cernboxPutFile", { timeout: editorTimeoutMs })
      .its("response.statusCode")
      .should("eq", net.webdavPutSaveStatus);

    cy.wait("@cernboxPropfindSpace", { timeout: editorTimeoutMs })
      .its("response.statusCode")
      .should("eq", net.webdavPropfindStatus);

    ensureFilesAppActive();

    const escaped = cssEscapeAttributeValue(fileName);
    cy.get(sel.resourceByName(escaped), { timeout: filesAppTimeoutMs }).should(
      "be.visible",
    );
  }

  return {
    ensureFilesAppActive,
    ensureFileExists,
    assertFileContent,
    createTextFile,
    stubWindowOpenForInTabNavigation,
  };
}
