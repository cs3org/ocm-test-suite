/// <reference types="cypress" />

import type { WebappShareLaunchArtifact } from "./webapp-share-launch-artifact";

const jupyterUiTimeoutMs = 90000;

export const jupyterLabUiSelector = [
  "#jupyterlab",
  ".jp-LabShell",
  "[data-jp-main-area]",
  ".jp-NotebookPanel",
  ".jp-Launcher",
  ".jp-FileBrowser",
].join(", ");

export const jupyterLabReadySelector = [
  ".jp-Launcher",
  ".jp-LauncherCard",
  ".jp-FileBrowser",
  ".jp-Notebook",
  ".jp-MainAreaWidget",
].join(", ");

export const jupyterLabFileListingSelector = ".jp-DirListing-item";

export function assertJupyterLabUiVisible(): void {
  cy.get("#jupyterlab-splash", { timeout: jupyterUiTimeoutMs }).should("not.exist");
  cy.get(jupyterLabReadySelector, { timeout: jupyterUiTimeoutMs })
    .filter(":visible")
    .first()
    .should("be.visible");

  cy.get("body", { timeout: jupyterUiTimeoutMs }).should(($body) => {
    const text = $body.text().replace(/\s+/g, " ").trim();
    expect(text, "Jupyter page body").to.not.match(/403\s*:?\s*Forbidden/i);
    expect(text, "Jupyter page body").to.not.match(/404\s*:?\s*Not Found/i);
  });
}

export function proveJupyterLabFromLaunchArtifact(
  artifact: WebappShareLaunchArtifact,
  screenshotName: string,
): void {
  if (artifact.receiverKind === "nextcloud") {
    cy.origin(
      artifact.hubOrigin,
      {
        args: {
          readySelector: jupyterLabReadySelector,
          fileListingSelector: jupyterLabFileListingSelector,
          screenshotName,
          timeout: jupyterUiTimeoutMs,
        },
      },
      ({ readySelector, fileListingSelector, screenshotName, timeout }) => {
        Cypress.on("uncaught:exception", (err) => {
          if (/unrecognized expression/i.test(err.message)) {
            return false;
          }
          return undefined;
        });
        // JupyterLab shows a splash (#jupyterlab-splash) while booting; wait for it
        // to clear so the screenshot shows the real Lab UI, not the loading spinner.
        cy.get("#jupyterlab-splash", { timeout }).should("not.exist");
        cy.get(readySelector, { timeout }).filter(":visible").first().should("be.visible");
        cy.get(fileListingSelector, { timeout })
          .filter(":visible")
          .should("be.visible")
          .should(($els) => {
            expect($els.text()).to.match(/\.ipynb/i);
          });
        cy.screenshot(screenshotName);
      },
    );
    return;
  }

  cy.location("pathname", { timeout: jupyterUiTimeoutMs }).should(
    "include",
    "/lab",
  );
  assertJupyterLabUiVisible();
  cy.get(jupyterLabFileListingSelector, { timeout: jupyterUiTimeoutMs })
    .filter(":visible")
    .should("be.visible")
    .should(($els) => {
      expect($els.text()).to.match(/\.ipynb/i);
    });
  cy.screenshot(screenshotName);
}
