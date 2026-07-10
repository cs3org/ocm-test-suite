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

export function proveJupyterLabFromLaunchArtifact(
  artifact: WebappShareLaunchArtifact,
  screenshotName: string,
): void {
  // Both Nextcloud and CERNBox launches hand off cross-origin to the remote hub
  // (the launch traffic never traverses the server-to-server OCM MITM). Assert
  // the terminal JupyterLab UI within the hub origin: the one bounded cy.origin
  // use allowed for this spec (see cypress/support/e2e.ts allowOriginForSpec).
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
}
