/// <reference types="cypress" />

import type { ShareWithSenderAdapter } from "../../../contracts/share-with";

export const ocmgoV1ShareWithSenderAdapter: ShareWithSenderAdapter = {
  key: "ocmgo/v1",

  prepareShareFile({ sharedFileName }) {
    const shareDir = "/artifacts/share";
    const sharePath = `${shareDir}/${sharedFileName}`;

    cy.exec(`mkdir -p ${shareDir}`, { log: false });
    cy.writeFile(
      sharePath,
      `OCMGo shared file: ${sharedFileName}\n`,
      { log: false },
    );
  },

  shareWithFederatedRecipient({ sharedFileName, federatedRecipientId }) {
    cy.visit("/ui/outgoing");
    cy.get("#outgoing-share-form", { timeout: 20000 }).should("be.visible");

    cy.get("#share-with", { timeout: 20000 }).clear().type(federatedRecipientId);
    cy.get("#local-path", { timeout: 20000 })
      .clear()
      .type(`/tmp/ocmts-share/${sharedFileName}`);
    cy.get("#share-submit", { timeout: 20000 }).click();

    cy.get("#share-result", { timeout: 20000 })
      .should("be.visible")
      .and("contain.text", "Share sent successfully");
  },
};

