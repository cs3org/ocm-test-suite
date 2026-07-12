/// <reference types="cypress" />

import type {
  WebappShareFlowReceiverAdapter,
  WebappShareIncomingShareRef,
} from "../../../contracts/webapp-share";
import type { NextcloudWebappShareVersion } from "./webapp-share-adapters";
import {
  assertHubLaunchOrigin,
  extractHubLaunchOriginFromRedirectHtml,
  type NextcloudWebappShareLaunchArtifact,
} from "../../../shared/webapp-share-launch-artifact";

const REMOTE_WEBAPP_APP_PATH = "/apps/ocmremotewebapp/";
const acceptTimeoutMs = 60000;
const launchTimeoutMs = 90000;

function ensureRemoteWebappAppActive(): void {
  cy.visit("/");

  cy.location("pathname", { timeout: 20000 }).then((pathname) => {
    if (typeof pathname === "string" && pathname.includes(REMOTE_WEBAPP_APP_PATH)) {
      return;
    }
    cy.visit(REMOTE_WEBAPP_APP_PATH);
  });

  cy.contains("h2", /Remote web app shares/i, { timeout: 20000 }).should("be.visible");
}

export function matchesIncomingWebappShareCardText(
  cardText: string,
  shareRef: WebappShareIncomingShareRef,
): boolean {
  const folderName = shareRef.sharedFolderName.trim();
  const senderFederatedId = shareRef.senderFederatedId.trim();
  const appName = shareRef.appName.trim();
  if (senderFederatedId.length === 0) {
    return false;
  }
  if (folderName.length === 0 && appName.length === 0) {
    return false;
  }

  // Match sender plus folder name or app name (cards title by appName).
  const normalized = cardText.replace(/\s+/g, " ").trim();
  const matchesResource =
    (folderName.length > 0 && normalized.includes(folderName)) ||
    (appName.length > 0 && normalized.includes(appName));
  return matchesResource && normalized.includes(senderFederatedId);
}

function summarizeShareCardTexts(items: JQuery<HTMLElement>): string {
  return Array.from(items)
    .map((element, index) => {
      const text = Cypress.$(element).text().replace(/\s+/g, " ").trim();
      const preview = text.length > 140 ? `${text.slice(0, 140)}...` : text;
      return `[${index}] ${preview}`;
    })
    .join("; ");
}

function findShareCard(
  shareRef: WebappShareIncomingShareRef,
): Cypress.Chainable<JQuery<HTMLElement>> {
  return cy.get("ul", { timeout: acceptTimeoutMs }).then(($list) => {
    const items = $list.find("li");
    const matches = items.filter((_, element) => {
      return matchesIncomingWebappShareCardText(
        Cypress.$(element).text(),
        shareRef,
      );
    });

    if (matches.length === 1) {
      return cy.wrap(matches.first());
    }

    const cardSummary = summarizeShareCardTexts(items);
    if (matches.length === 0) {
      throw new Error(
        [
          "Could not find a unique ocmremotewebapp share card.",
          `resource="${shareRef.sharedFolderName}"`,
          `sender="${shareRef.senderFederatedId}"`,
          `app="${shareRef.appName}"`,
          `Visible cards: ${items.length}.`,
          `Card texts: ${cardSummary}`,
        ].join(" "),
      );
    }

    throw new Error(
      [
        "Ambiguous ocmremotewebapp share card match.",
        `resource="${shareRef.sharedFolderName}"`,
        `sender="${shareRef.senderFederatedId}"`,
        `app="${shareRef.appName}"`,
        `Matched cards: ${matches.length}.`,
        `Card texts: ${cardSummary}`,
      ].join(" "),
    );
  });
}

function chooseThisTabTargetIfPresent(): void {
  cy.get("body").then(($body) => {
    const hasTargetPicker =
      $body.find('[aria-label="Open in"], [aria-label-combobox="Open in"]').filter(":visible")
        .length > 0;

    if (!hasTargetPicker) {
      return;
    }

    cy.get('[aria-label="Open in"], [aria-label-combobox="Open in"]', {
      timeout: 20000,
    })
      .filter(":visible")
      .first()
      .click({ force: true });

    cy.contains('[role="option"], li, span', /^This tab$/i, { timeout: 20000 })
      .should("be.visible")
      .click({ force: true });
  });
}

export function createNextcloudWebappShareReceiverAdapter(
  version: NextcloudWebappShareVersion,
): WebappShareFlowReceiverAdapter {
  const key = `nextcloud/${version}`;

  return {
    key,
    // Nextcloud launch traffic stays on browser-to-hub paths the MITM does not proxy.
    mitmLaunchExpectations: [],

    acceptIncomingWebappShare(shareRef) {
      ensureRemoteWebappAppActive();

      cy.intercept("POST", "**/apps/ocmremotewebapp/api/v1/shares/**/accept").as(
        "nextcloudRemoteWebappAccept",
      );

      findShareCard(shareRef).within(() => {
        cy.contains("button", /^\s*Accept\s*$/i, { timeout: acceptTimeoutMs })
          .should("be.visible")
          .click();
      });

      cy.wait("@nextcloudRemoteWebappAccept", { timeout: acceptTimeoutMs }).then(
        (interception) => {
          const statusCode = interception.response?.statusCode;
          expect(statusCode, "Nextcloud remote webapp accept status code").to.be.oneOf([
            200, 201,
          ]);
        },
      );

      findShareCard(shareRef).within(() => {
        cy.contains(/accepted/i, { timeout: acceptTimeoutMs }).should("be.visible");
        cy.contains("button", /^\s*Open\s*$/i, { timeout: acceptTimeoutMs }).should("be.visible");
      });
    },

    launchRemoteWebapp(shareRef) {
      ensureRemoteWebappAppActive();
      findShareCard(shareRef).should("be.visible");

      let hubOrigin: string | null = null;

      cy.intercept("GET", "**/apps/ocmremotewebapp/ocm/open/**", (req) => {
        req.continue((res) => {
          const status = res.statusCode ?? 0;
          if (status >= 200 && status < 300 && typeof res.body === "string") {
            const origin = extractHubLaunchOriginFromRedirectHtml(res.body);
            if (origin) {
              hubOrigin = origin;
            }
          }
        });
      }).as("nextcloudRemoteWebappOpen");

      chooseThisTabTargetIfPresent();

      findShareCard(shareRef).within(() => {
        cy.contains("button", /^\s*Open\s*$/i, { timeout: launchTimeoutMs })
          .should("be.visible")
          .click();
      });

      return cy
        .wait("@nextcloudRemoteWebappOpen", { timeout: launchTimeoutMs })
        .then((interception) => {
          const requestUrl = interception.request.url ?? "";
          expect(requestUrl, "Nextcloud remote webapp open URL").to.include(
            "target=redirect",
          );
          const receiverOrigin = new URL(String(Cypress.config("baseUrl"))).origin;
          assertHubLaunchOrigin(hubOrigin, receiverOrigin);
          const artifact: NextcloudWebappShareLaunchArtifact = {
            receiverKind: "nextcloud",
            launchGate: "cross-origin-open",
            hubOrigin: hubOrigin as string,
            openRequestUrl: requestUrl,
          };
          return cy.wrap(artifact);
        });
    },
  };
}
