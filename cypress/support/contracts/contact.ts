/// <reference types="cypress" />

import type { ActorCredentials } from "./login";

export type ContactTokenSenderAdapter = {
  key: string;
  createInviteToken(params: { note: string }): Cypress.Chainable<string>;
};

export type ContactTokenReceiverAdapter = {
  key: string;
  acceptInviteToken(params: {
    inviteToken: string;
  }): Cypress.Chainable<string>;
  assertAcceptedContactExists(params: {
    acceptedContactUrl: string;
  }): void;
};

export type ContactWayfSenderAdapter = {
  key: string;
  createInviteLink(params: { note: string }): Cypress.Chainable<string>;
  captureReceiverRedirectUrl(params: {
    inviteLink: string;
    providerUrl: string;
  }): Cypress.Chainable<string>;
};

export type ContactWayfReceiverAdapter = {
  key: string;
  acceptInviteFromRedirect(params: {
    redirectUrl: string;
  }): Cypress.Chainable<string>;
  assertAcceptedContactExists(params: {
    acceptedContactUrl: string;
  }): void;
};

export type ProviderIdentityAdapter = {
  key: string;
  getBaseUrl(): string;
  getProviderUrl(params?: { inviteLink?: string }): string;
  getHost(): string;
  buildFederatedRecipientId(params: { credentials: ActorCredentials }): string;
};
