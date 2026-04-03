/// <reference types="cypress" />

import type {
  ShareWithReceiverAdapter,
  ShareWithSenderAdapter,
} from "../../../contracts/share-with";
import {
  ensureFileExists,
  ensureFilesAppActive,
  ensureFilesAppLoadedForShareAcceptance,
  renameFile,
} from "./shared-files";
import { addExternalShare, handleShareAcceptance, openSharingPanel } from "./shared-sharing";

export const nextcloudV33ShareWithSenderAdapter: ShareWithSenderAdapter = {
  key: "nextcloud/v33",

  prepareShareFile({ sourceFileName = "welcome.txt", sharedFileName }) {
    ensureFilesAppActive();

    cy.log(`prepare share file: ${sourceFileName} -> ${sharedFileName}`);

    ensureFileExists(sourceFileName);
    renameFile(sourceFileName, sharedFileName);
    ensureFileExists(sharedFileName);
  },

  shareWithFederatedRecipient({ sharedFileName, federatedRecipientId }) {
    ensureFilesAppActive();

    cy.log(`share ${sharedFileName} -> ${federatedRecipientId}`);

    openSharingPanel(sharedFileName);
    addExternalShare(federatedRecipientId);
  },
};

export const nextcloudV33ShareWithReceiverAdapter: ShareWithReceiverAdapter = {
  key: "nextcloud/v33",

  acceptIncomingShare({ sharedFileName }) {
    ensureFilesAppLoadedForShareAcceptance();

    handleShareAcceptance(sharedFileName, { remainingAttempts: 3 });
  },
};
