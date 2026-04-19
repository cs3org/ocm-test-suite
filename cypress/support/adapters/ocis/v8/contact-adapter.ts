/// <reference types="cypress" />

import type {
  ContactTokenReceiverAdapter,
  ContactTokenSenderAdapter,
  ProviderIdentityAdapter,
} from "../../../contracts/contact";
import type { ActorCredentials } from "../../../contracts/login";
import {
  acceptOcmInviteToken,
  assertOcmConnectionExists,
  createOcmInviteTokenBase64,
  resolveOcmReceiverBaseUrl,
} from "../shared/contacts-ocm-invites";

export const ocisV8ContactTokenSenderAdapter: ContactTokenSenderAdapter = {
  key: "ocis/v8",

  createInviteToken({ note }) {
    return createOcmInviteTokenBase64(note);
  },
};

export const ocisV8ContactTokenReceiverAdapter: ContactTokenReceiverAdapter = {
  key: "ocis/v8",

  acceptInviteToken({ inviteToken }) {
    return acceptOcmInviteToken(inviteToken);
  },

  assertAcceptedContactExists({ acceptedContactUrl }) {
    assertOcmConnectionExists({ acceptedContactUrl });
  },
};

export const ocisV8ProviderIdentityAdapter: ProviderIdentityAdapter = {
  key: "ocis/v8",

  getBaseUrl() {
    return resolveOcmReceiverBaseUrl();
  },

  getProviderUrl() {
    return new URL(resolveOcmReceiverBaseUrl()).origin;
  },

  getHost() {
    return new URL(resolveOcmReceiverBaseUrl()).host;
  },

  buildFederatedRecipientId({ credentials }: { credentials: ActorCredentials }) {
    const host = new URL(resolveOcmReceiverBaseUrl()).host;
    return `${credentials.username}@${host}`;
  },
};
