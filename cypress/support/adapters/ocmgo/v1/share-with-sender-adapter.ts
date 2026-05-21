/// <reference types="cypress" />

import type { ShareWithFlowSenderAdapter } from "../../../contracts/share-with";
import type { ShareFileSenderAdapter } from "../../../contracts/share-file";

// UI form path: sender-container mount point for the source file.
const SHARE_DIR = "/tmp/ocmts-share";

// Runner-visible path: the shared host artifacts mount exposed to the
// Cypress runner. The sender platform container mounts
// ${OCMTS_ARTIFACTS_BASE}/share at /tmp/ocmts-share, so writing here
// makes the file visible inside the sender container at SHARE_DIR.
const ARTIFACTS_SHARE_DIR = "/artifacts/share";

function prepareShareFileImpl(
  { sharedFileName, sourceFileName: _sourceFileName }: { sharedFileName: string; sourceFileName?: string },
): Cypress.Chainable<{ expectedContent?: string }> {
  const artifactsPath = `${ARTIFACTS_SHARE_DIR}/${sharedFileName}`;

  cy.exec(`mkdir -p ${ARTIFACTS_SHARE_DIR}`, { log: false });
  cy.writeFile(
    artifactsPath,
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
