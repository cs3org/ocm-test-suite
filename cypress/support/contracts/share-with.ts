/// <reference types="cypress" />

import type { ActorCredentials, ActorRef, LoginAdapter } from "./login";

export type ShareWithSenderAdapter = {
  key: string;
  prepareShareFile(params: {
    sharedFileName: string;
    sourceFileName?: string;
  }): void;
  shareWithFederatedRecipient(params: {
    sharedFileName: string;
    federatedRecipientId: string;
  }): void;
};

export type ShareWithReceiverAdapter = {
  key: string;
  acceptIncomingShare(params: { sharedFileName: string }): void;
};

export type ScenarioCase = {
  id: string;
  senderAdapter: ShareWithSenderAdapter;
  receiverAdapter: ShareWithReceiverAdapter;
  senderLogin: LoginAdapter;
  receiverLogin: LoginAdapter;
  sender: ActorRef;
  receiver: ActorRef;
};

export type { ActorCredentials, ActorRef };
