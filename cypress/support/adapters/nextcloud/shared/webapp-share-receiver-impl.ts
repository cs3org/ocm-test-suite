/// <reference types="cypress" />

import type {
  WebappShareFlowReceiverAdapter,
  WebappShareIncomingShareRef,
} from "../../../contracts/webapp-share";

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
  if (folderName.length === 0 || senderFederatedId.length === 0) {
    return false;
  }

  const normalized = cardText.replace(/\s+/g, " ").trim();
  return (
    normalized.includes(folderName) && normalized.includes(senderFederatedId)
  );
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
        `Matched cards: ${matches.length}.`,
        `Card texts: ${cardSummary}`,
      ].join(" "),
    );
  });
}

function chooseThisTabTargetWithinShareCard(): void {
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
  version: "v35",
): WebappShareFlowReceiverAdapter {
  const key = `nextcloud/${version}`;

  return {
    key,

    acceptIncomingWebappShare(shareRef) {
      ensureRemoteWebappAppActive();

      cy.intercept("POST", "**/apps/ocmremotewebapp/api/v1/shares/**/accept").as(
        "nextcloudRemoteWebappAccept",
      );

      findShareCard(shareRef).within(() => {
        cy.contains("button", /^Accept$/i, { timeout: acceptTimeoutMs })
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
        cy.contains("button", /^Open$/i, { timeout: acceptTimeoutMs }).should("be.visible");
      });
    },

    launchRemoteWebapp(shareRef) {
      ensureRemoteWebappAppActive();
      findShareCard(shareRef).should("be.visible");

      cy.intercept("GET", "**/apps/ocmremotewebapp/ocm/open/**").as(
        "nextcloudRemoteWebappOpen",
      );

      findShareCard(shareRef).within(() => {
        chooseThisTabTargetWithinShareCard();
        cy.contains("button", /^Open$/i, { timeout: launchTimeoutMs })
          .should("be.visible")
          .click();
      });

      cy.wait("@nextcloudRemoteWebappOpen", { timeout: launchTimeoutMs }).then(
        (interception) => {
          const requestUrl = interception.request.url ?? "";
          expect(requestUrl, "Nextcloud remote webapp open URL").to.include(
            "target=redirect",
          );
        },
      );

      cy.location("pathname", { timeout: launchTimeoutMs }).should(
        "include",
        "/apps/ocmremotewebapp/ocm/open/",
      );
    },
  };
}
