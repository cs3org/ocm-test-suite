/// <reference types="cypress" />

import type { ShareWithAdapter } from "../../../contracts/share-with";
import {
  ensureFileExists,
  ensureFilesAppActive,
  ensureFilesAppLoadedForShareAcceptance,
  renameFile,
} from "./shared-files";
import { addExternalShare, handleShareAcceptance, openSharingPanel } from "./shared-sharing";

export const nextcloudV33ShareWithAdapter: ShareWithAdapter = {
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

  acceptIncomingShare({ sharedFileName }) {
    ensureFilesAppLoadedForShareAcceptance();

    handleShareAcceptance(sharedFileName, { remainingAttempts: 3 });
  },
};
