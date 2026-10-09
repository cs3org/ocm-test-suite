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
  // Navigation stays receiver-specific. CERNBox has already replayed the handoff
  // and verified cookie-authenticated contents before its commanded Lab visit.
  // Nextcloud retains its GET ocm/open navigation. Both share this hub UI proof.
  cy.origin(
    artifact.hubOrigin,
    {
      args: {
        readySelector: jupyterLabReadySelector,
        fileListingSelector: jupyterLabFileListingSelector,
        screenshotName,
        timeout: jupyterUiTimeoutMs,
        labUrl: artifact.receiverKind === "cernbox" && artifact.launchGate === "request-replay"
          ? artifact.labUrl
          : null,
      },
    },
    ({ readySelector, fileListingSelector, screenshotName, timeout, labUrl }) => {
      Cypress.on("uncaught:exception", (err) => {
        if (/unrecognized expression/i.test(err.message)) {
          return false;
        }
        return undefined;
      });
      if (labUrl) {
        cy.visit(labUrl, { log: false });
        cy.location("origin").should("equal", new URL(labUrl).origin);
        cy.location("pathname").should("match", /^\/user\/[^/]+\/(?:[^/]+\/)?lab(?:\/.*)?$/);
      }
      // Wait for the real Lab UI after its splash, then prove the notebook.
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
  cy.task("launch-probe:stop", null, { log: false });
}
