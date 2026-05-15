/// <reference types="cypress" />

import type { ShareWithFlowReceiverAdapter } from "../../../contracts/share-with";
import type { ShareFileReceiverAdapter } from "../../../contracts/share-file";

function acceptIncomingShareImpl({ sharedFileName }: { sharedFileName: string }): void {
  cy.visit("/ui/inbox");

  cy.get(".share-item", { timeout: 20000 }).should("exist");

  cy.contains(".share-item .share-name", sharedFileName, { timeout: 20000 })
    .closest(".share-item")
    .scrollIntoView()
    .within(() => {
      cy.get("button.btn-accept, .btn-accept", { timeout: 20000 })
        .first()
        .click();
    });

  cy.contains(".share-item .share-name", sharedFileName, { timeout: 20000 })
    .closest(".share-item")
    .should(($item) => {
      const hasAcceptedClass = $item.find(".status-accepted").length > 0;
      const statusText = $item.find(".share-status").text().toLowerCase();
      expect(hasAcceptedClass || statusText.includes("accepted")).to.eq(true);
    });
}

export const ocmgoV1ShareWithFlowReceiverAdapter: ShareWithFlowReceiverAdapter = {
  key: "ocmgo/v1",
  acceptIncomingShare: acceptIncomingShareImpl,
};

export const ocmgoV1ShareFileReceiverAdapter: ShareFileReceiverAdapter = {
  key: "ocmgo/v1",
  acceptIncomingShare: acceptIncomingShareImpl,
};
