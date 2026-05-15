/// <reference types="cypress" />

import type { ActorCredentials, ActorRef, LoginAdapter } from "./login";

// Flow entry point for the unknown-party share-with flow. Adapters that
// implement this support direct sharing with a remote party that has no
// prior contact relationship.
export type ShareWithFlowSenderAdapter = {
  key: string;
  prepareShareFile(params: {
    sharedFileName: string;
    sourceFileName?: string;
  }): Cypress.Chainable<{ expectedContent?: string }>;
  shareWithFederatedRecipient(params: {
    sharedFileName: string;
    federatedRecipientId: string;
  }): void;
};

export type ShareWithFlowReceiverAdapter = {
  key: string;
  acceptIncomingShare(params: { sharedFileName: string }): void;
  assertSharedFileContent?(params: {
    sharedFileName: string;
    expectedContent: string;
  }): void;
};

// ScenarioCase for the share-with flow's own cases.ts. Uses the FLOW
// adapter types (not the file-op types).
export type ScenarioCase = {
  id: string;
  senderAdapter: ShareWithFlowSenderAdapter;
  receiverAdapter: ShareWithFlowReceiverAdapter;
  senderLogin: LoginAdapter;
  receiverLogin: LoginAdapter;
  sender: ActorRef;
  receiver: ActorRef;
};

export type { ActorCredentials, ActorRef };
