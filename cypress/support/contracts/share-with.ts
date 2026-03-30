/// <reference types="cypress" />

import type { ActorCredentials, ActorRef } from "./login";

export type ShareWithAdapter = {
  key: string;
  prepareShareFile(params: {
    sharedFileName: string;
    sourceFileName?: string;
  }): void;
  shareWithFederatedRecipient(params: {
    sharedFileName: string;
    federatedRecipientId: string;
  }): void;
  acceptIncomingShare(params: { sharedFileName: string }): void;
};

export type ScenarioCase = {
  id: string;
  adapter: ShareWithAdapter;
  sender: ActorRef;
  receiver: ActorRef;
};

export type { ActorCredentials, ActorRef };
