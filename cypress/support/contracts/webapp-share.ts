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
  openWebappShareDialog(params: { sharedFolderName: string }): void;
  submitWebappShare(params: { federatedRecipientId: string }): void;
  shareWebappWithFederatedRecipient(params: {
    sharedFolderName: string;
    federatedRecipientId: string;
  }): void;
};

export type WebappShareIncomingShareRef = {
  sharedFolderName: string;
  senderFederatedId: string;
};

export function buildSenderFederatedId(params: {
  username: string;
  host: string;
}): string {
  const username = params.username.trim();
  const host = params.host.trim();
  if (username.length === 0 || host.length === 0) {
    throw new Error(
      [
        "Cannot build sender federated id without username and host.",
        `username="${username}", host="${host}".`,
      ].join(" "),
    );
  }
  return `${username}@${host}`;
}

export type WebappShareFlowReceiverAdapter = {
  key: string;
  acceptIncomingWebappShare(params: WebappShareIncomingShareRef): void;
  launchRemoteWebapp(params: WebappShareIncomingShareRef): void;
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
