/// <reference types="cypress" />

import type {
  ContactTokenReceiverAdapter,
  ContactTokenSenderAdapter,
  ProviderIdentityAdapter,
} from "../../../contracts/contact";
import type { ActorCredentials } from "../../../contracts/login";
import {
  acceptOpenCloudInviteToken,
  assertOpenCloudConnectionExists,
  createOpenCloudInviteTokenBase64,
  resolveOpenCloudOcmReceiverBaseUrl,
} from "../shared/contacts-ocm-invites";

export const opencloudV6ContactTokenSenderAdapter: ContactTokenSenderAdapter = {
  key: "opencloud/v6",

  createInviteToken({ note }) {
    return createOpenCloudInviteTokenBase64(note);
  },
};

export const opencloudV6ContactTokenReceiverAdapter: ContactTokenReceiverAdapter = {
  key: "opencloud/v6",

  acceptInviteToken({ inviteToken }) {
    return acceptOpenCloudInviteToken(inviteToken);
  },

  assertAcceptedContactExists({ acceptedContactUrl }) {
    assertOpenCloudConnectionExists({ acceptedContactUrl });
  },
};

export const opencloudV6ProviderIdentityAdapter: ProviderIdentityAdapter = {
  key: "opencloud/v6",

  getBaseUrl() {
    return resolveOpenCloudOcmReceiverBaseUrl();
  },

  getProviderUrl() {
    return new URL(resolveOpenCloudOcmReceiverBaseUrl()).origin;
  },

  getHost() {
    return new URL(resolveOpenCloudOcmReceiverBaseUrl()).host;
  },

  buildFederatedRecipientId({ credentials }: { credentials: ActorCredentials }) {
    const host = new URL(resolveOpenCloudOcmReceiverBaseUrl()).host;
    return `${credentials.username}@${host}`;
  },
};
