/// <reference types="cypress" />

import type {
  ContactTokenReceiverAdapter,
  ContactTokenSenderAdapter,
  ProviderIdentityAdapter,
} from "../../../contracts/contact";
import type { ActorCredentials } from "../../../contracts/login";
import {
  acceptCernboxInviteToken,
  assertCernboxConnectionExists,
  createCernboxInviteTokenBase64,
  resolveCernboxOcmReceiverBaseUrl,
} from "../shared/contacts-ocm-invites";

export const cernboxV11ContactTokenSenderAdapter: ContactTokenSenderAdapter = {
  key: "cernbox/v11",

  createInviteToken({ note }) {
    return createCernboxInviteTokenBase64(note);
  },
};

export const cernboxV11ContactTokenReceiverAdapter: ContactTokenReceiverAdapter =
  {
    key: "cernbox/v11",

    acceptInviteToken({ inviteToken }) {
      return acceptCernboxInviteToken(inviteToken);
    },

    assertAcceptedContactExists({ acceptedContactUrl }) {
      assertCernboxConnectionExists({ acceptedContactUrl });
    },
  };

export const cernboxV11ProviderIdentityAdapter: ProviderIdentityAdapter = {
  key: "cernbox/v11",

  getBaseUrl() {
    return resolveCernboxOcmReceiverBaseUrl();
  },

  getProviderUrl() {
    return new URL(resolveCernboxOcmReceiverBaseUrl()).origin;
  },

  getHost() {
    return new URL(resolveCernboxOcmReceiverBaseUrl()).host;
  },

  buildFederatedRecipientId({ credentials }: { credentials: ActorCredentials }) {
    const host = new URL(resolveCernboxOcmReceiverBaseUrl()).host;
    return `${credentials.username}@${host}`;
  },
};
