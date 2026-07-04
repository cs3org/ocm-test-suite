/// <reference types="cypress" />

import type {
  ShareWithFlowReceiverAdapter,
  ShareWithFlowSenderAdapter,
} from "../../../contracts/share-with";
import type {
  ShareFileReceiverAdapter,
  ShareFileSenderAdapter,
} from "../../../contracts/share-file";
import {
  downloadAndAssertNextcloudSharedFile,
  downloadAndReadNextcloudFile,
  ensureFileExists,
  ensureFilesAppActive,
  ensureFilesAppLoadedForShareAcceptance,
  renameFile,
} from "./files";
import { addExternalShare, handleShareAcceptance, openSharingPanel } from "./sharing";

export type NextcloudShareWithVersion = "v32" | "v33" | "v34" | "v35";

export type NextcloudShareWithAdapters = {
  shareWithFlowSender: ShareWithFlowSenderAdapter;
  shareWithFlowReceiver: ShareWithFlowReceiverAdapter;
  shareFileSender: ShareFileSenderAdapter;
  shareFileReceiver: ShareFileReceiverAdapter;
};

export function createNextcloudShareWithAdapters(
  version: NextcloudShareWithVersion,
): NextcloudShareWithAdapters {
  const key = `nextcloud/${version}`;

  function prepareShareFile(
    { sourceFileName = "welcome.txt", sharedFileName }: { sourceFileName?: string; sharedFileName: string },
  ): Cypress.Chainable<{ expectedContent?: string }> {
    ensureFilesAppActive();
    cy.log(`prepare share file: ${sourceFileName} -> ${sharedFileName}`);
    ensureFileExists(sourceFileName);
    renameFile(sourceFileName, sharedFileName);
    ensureFileExists(sharedFileName);
    return downloadAndReadNextcloudFile(sharedFileName).then((content) => ({ expectedContent: content }));
  }

  function shareFile(
    { sharedFileName, federatedRecipientId }: { sharedFileName: string; federatedRecipientId: string },
  ): void {
    ensureFilesAppActive();
    cy.log(`share ${sharedFileName} -> ${federatedRecipientId}`);
    openSharingPanel(sharedFileName);
    addExternalShare(federatedRecipientId);
  }

  function acceptIncomingShare({ sharedFileName }: { sharedFileName: string }): void {
    ensureFilesAppLoadedForShareAcceptance();
    handleShareAcceptance(sharedFileName, { remainingAttempts: 3 });
  }

  function assertSharedFileContent(
    { sharedFileName, expectedContent }: { sharedFileName: string; expectedContent: string },
  ): void {
    downloadAndAssertNextcloudSharedFile(sharedFileName, expectedContent);
  }

  return {
    shareWithFlowSender: {
      key,
      prepareShareFile,
      shareWithFederatedRecipient: shareFile,
    },
    shareWithFlowReceiver: {
      key,
      acceptIncomingShare,
      assertSharedFileContent,
    },
    shareFileSender: {
      key,
      prepareShareFile,
      sendFileToFederatedRecipient: shareFile,
    },
    shareFileReceiver: {
      key,
      acceptIncomingShare,
      assertSharedFileContent,
    },
  };
}
