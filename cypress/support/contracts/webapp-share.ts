/// <reference types="cypress" />

import type {
  ContactTokenReceiverAdapter,
  ContactTokenSenderAdapter,
  ProviderIdentityAdapter,
} from "./contact";
import type { ActorRef, LoginAdapter } from "./login";

export type WebappShareFlowSenderAdapter = {
  key: string;
  prepareShareFolder(params: { sharedFolderName: string }): void;
  shareWebappWithFederatedRecipient(params: {
    sharedFolderName: string;
    federatedRecipientId: string;
  }): void;
};

export type WebappShareFlowReceiverAdapter = {
  key: string;
  acceptIncomingWebappShare(params: { sharedFolderName: string }): void;
  launchRemoteWebapp(params: { sharedFolderName: string }): void;
};

export type ScenarioCase = {
  id: string;
  sender: ActorRef;
  receiver: ActorRef;
  senderLogin: LoginAdapter;
  receiverLogin: LoginAdapter;
  contactTokenSender: ContactTokenSenderAdapter;
  contactTokenReceiver: ContactTokenReceiverAdapter;
  receiverIdentity: ProviderIdentityAdapter;
  senderAdapter: WebappShareFlowSenderAdapter;
  receiverAdapter: WebappShareFlowReceiverAdapter;
};
