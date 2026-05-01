/// <reference types="cypress" />

import type { ShareWithFlowSenderAdapter } from "../../../contracts/share-with";
import type { ShareFileSenderAdapter } from "../../../contracts/share-file";

// Must match the OCMGo share-creation form's source-file input default.
const SHARE_DIR = "/tmp/ocmts-share";

function prepareShareFileImpl(
  { sharedFileName, sourceFileName: _sourceFileName }: { sharedFileName: string; sourceFileName?: string },
): Cypress.Chainable<{ expectedContent?: string }> {
  const sharePath = `${SHARE_DIR}/${sharedFileName}`;

  cy.exec(`mkdir -p ${SHARE_DIR}`, { log: false });
  cy.writeFile(
    sharePath,
    `OCMGo shared file: ${sharedFileName}\n`,
    { log: false },
  );
  return cy.wrap({});
}

function sendShareImpl({ sharedFileName, federatedRecipientId }: { sharedFileName: string; federatedRecipientId: string }): void {
  cy.visit("/ui/outgoing");
  cy.get("#outgoing-share-form", { timeout: 20000 }).should("be.visible");

  cy.get("#share-with", { timeout: 20000 }).clear().type(federatedRecipientId);
  cy.get("#local-path", { timeout: 20000 })
    .clear()
    .type(`${SHARE_DIR}/${sharedFileName}`);
  cy.get("#share-submit", { timeout: 20000 }).click();

  cy.get("#share-result", { timeout: 20000 })
    .should("be.visible")
    .and("contain.text", "Share sent successfully");
}

export const ocmgoV1ShareWithFlowSenderAdapter: ShareWithFlowSenderAdapter = {
  key: "ocmgo/v1",
  prepareShareFile: prepareShareFileImpl,
  shareWithFederatedRecipient: sendShareImpl,
};

export const ocmgoV1ShareFileSenderAdapter: ShareFileSenderAdapter = {
  key: "ocmgo/v1",
  prepareShareFile: prepareShareFileImpl,
  sendFileToFederatedRecipient: sendShareImpl,
};
