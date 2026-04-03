/// <reference types="cypress" />

import type { ShareWithReceiverAdapter } from "../../../contracts/share-with";

export const ocmgoV1ShareWithReceiverAdapter: ShareWithReceiverAdapter = {
  key: "ocmgo/v1",

  acceptIncomingShare({ sharedFileName }) {
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
  },
};

