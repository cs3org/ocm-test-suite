/// <reference types="cypress" />

// Post-contact file sharing operation. Used by contact-token and contact-wayf
// flows after the federated contact has been established. Distinct from the
// share-with FLOW: any adapter that exposes a federated-share-with-known-
// contact code path can implement this, including vendors that do NOT support
// the unknown-party share-with flow.
export type ShareFileSenderAdapter = {
  key: string;
  prepareShareFile(params: {
    sharedFileName: string;
    sourceFileName?: string;
  }): Cypress.Chainable<{ expectedContent?: string }>;
  sendFileToFederatedRecipient(params: {
    sharedFileName: string;
    federatedRecipientId: string;
  }): void;
};

export type ShareFileReceiverAdapter = {
  key: string;
  acceptIncomingShare(params: { sharedFileName: string }): void;
  assertSharedFileContent?(params: {
    sharedFileName: string;
    expectedContent: string;
  }): void;
};
