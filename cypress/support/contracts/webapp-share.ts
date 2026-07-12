/// <reference types="cypress" />

import type {
  ContactTokenReceiverAdapter,
  ContactTokenSenderAdapter,
  ProviderIdentityAdapter,
} from "./contact";
import type { ActorCredentials, ActorRef, LoginAdapter } from "./login";
import type { MitmExpectation } from "../shared/mitm-traffic";
import type { WebappShareLaunchArtifact } from "../shared/webapp-share-launch-artifact";

export type { WebappShareLaunchArtifact } from "../shared/webapp-share-launch-artifact";

export type WebappShareFlowSenderAdapter = {
  key: string;
  prepareShareFolder(params: {
    sharedFolderName: string;
    credentials: ActorCredentials;
  }): void;
  openWebappShareDialog(params: { sharedFolderName: string }): void;
  submitWebappShare(params: { federatedRecipientId: string }): void;
};

export type WebappShareIncomingShareRef = {
  sharedFolderName: string;
  senderFederatedId: string;
  appName: string;
};

// Receiver cards title shares by webapp appName, not folder name.
export const WEBAPP_SHARE_APP_NAME = "Jupyter";

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
  mitmLaunchExpectations: MitmExpectation[];
  acceptIncomingWebappShare(params: WebappShareIncomingShareRef): void;
  launchRemoteWebapp(
    params: WebappShareIncomingShareRef,
  ): Cypress.Chainable<WebappShareLaunchArtifact>;
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
