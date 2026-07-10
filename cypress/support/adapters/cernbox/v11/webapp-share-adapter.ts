/// <reference types="cypress" />

import type { WebappShareFlowReceiverAdapter } from "../../../contracts/webapp-share";
import type { CernboxWebappShareLaunchArtifact } from "../../../shared/webapp-share-launch-artifact";
import {
  assertHubLaunchOrigin,
  extractHubLaunchOriginFromOpenInApp,
} from "../../../shared/webapp-share-launch-artifact";
import { cssEscapeAttributeValue } from "../../../shared/selectors";
import { makeCernboxFilesHelpers } from "../shared/files";
import { makeCernboxSharingHelpers } from "../shared/sharing";
import { cernboxV11Profile } from "./profile";

const files = makeCernboxFilesHelpers(cernboxV11Profile);
const sharing = makeCernboxSharingHelpers(cernboxV11Profile, files);
const sel = cernboxV11Profile.selectors.sharing;
const sharesNavTimeoutMs = 60000;
const launchTimeoutMs = 90000;

function openReceivedFolderMenu(sharedFolderName: string): void {
  const escapedName = cssEscapeAttributeValue(sharedFolderName);

  sharing.openSharesWithMe();
  sharing.openResourceContextMenu(
    sel.receivedResourceByName(escapedName),
    sharesNavTimeoutMs,
  );
}

export const cernboxV11WebappShareFlowReceiverAdapter: WebappShareFlowReceiverAdapter =
  {
    key: "cernbox/v11",

    acceptIncomingWebappShare({ sharedFolderName }) {
      sharing.acceptIncomingShare(sharedFolderName);
    },

    launchRemoteWebapp({ sharedFolderName }) {
      // Keep the launch in-tab: the "Open remotely" action pre-opens a named
      // popup then form-POSTs the launch into it. The stub names the current
      // window so the POST targets this tab.
      files.stubWindowOpenForInTabNavigation();

      // Observe (do not modify) the open-in-app response; the app_url in its
      // JSON body is the cross-origin remote hub the browser then POSTs into.
      cy.intercept("POST", "**/sciencemesh/open-in-app").as("cernboxOpenInApp");

      openReceivedFolderMenu(sharedFolderName);

      cy.get(sel.contextMenu)
        .contains(
          'button, [role="menuitem"], li, span',
          /Open remotely/i,
          { timeout: sharesNavTimeoutMs },
        )
        .should("be.visible")
        .click({ force: true });

      const receiverOrigin = new URL(String(Cypress.config("baseUrl"))).origin;

      return cy
        .wait("@cernboxOpenInApp", { timeout: launchTimeoutMs })
        .then((interception) => {
          const statusCode = interception.response?.statusCode;
          expect(statusCode, "CERNBox open-in-app status code").to.be.oneOf([
            200, 201, 204,
          ]);

          const hubOrigin = extractHubLaunchOriginFromOpenInApp(
            interception.response?.body,
          );
          assertHubLaunchOrigin(hubOrigin, receiverOrigin);

          const artifact: CernboxWebappShareLaunchArtifact = {
            receiverKind: "cernbox",
            launchGate: "cross-origin-open",
            hubOrigin: hubOrigin as string,
          };
          return cy.wrap(artifact);
        });
    },
  };
