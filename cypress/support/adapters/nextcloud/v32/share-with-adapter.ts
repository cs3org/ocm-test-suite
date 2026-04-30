/// <reference types="cypress" />

import type { ShareWithFlowReceiverAdapter, ShareWithFlowSenderAdapter } from "../../../contracts/share-with";
import type { ShareFileReceiverAdapter, ShareFileSenderAdapter } from "../../../contracts/share-file";
import {
  downloadAndAssertNextcloudSharedFile,
  downloadAndReadNextcloudFile,
  ensureFileExists,
  ensureFilesAppActive,
  ensureFilesAppLoadedForShareAcceptance,
  renameFile,
} from "../shared/files";
import { addExternalShare, handleShareAcceptance, openSharingPanel } from "../shared/sharing";

function prepareShareFileImpl(
  { sourceFileName = "welcome.txt", sharedFileName }: { sourceFileName?: string; sharedFileName: string },
): Cypress.Chainable<{ expectedContent?: string }> {
  ensureFilesAppActive();
  cy.log(`prepare share file: ${sourceFileName} -> ${sharedFileName}`);
  ensureFileExists(sourceFileName);
  renameFile(sourceFileName, sharedFileName);
  ensureFileExists(sharedFileName);
  return downloadAndReadNextcloudFile(sharedFileName).then((content) => ({ expectedContent: content }));
}

function shareFileImpl({ sharedFileName, federatedRecipientId }: { sharedFileName: string; federatedRecipientId: string }): void {
  ensureFilesAppActive();
  cy.log(`share ${sharedFileName} -> ${federatedRecipientId}`);
  openSharingPanel(sharedFileName);
  addExternalShare(federatedRecipientId);
}

function acceptIncomingShareImpl({ sharedFileName }: { sharedFileName: string }): void {
  ensureFilesAppLoadedForShareAcceptance();
  handleShareAcceptance(sharedFileName, { remainingAttempts: 3 });
}

function assertSharedFileContentImpl({ sharedFileName, expectedContent }: { sharedFileName: string; expectedContent: string }): void {
  downloadAndAssertNextcloudSharedFile(sharedFileName, expectedContent);
}

export const nextcloudV32ShareWithFlowSenderAdapter: ShareWithFlowSenderAdapter = {
  key: "nextcloud/v32",
  prepareShareFile: prepareShareFileImpl,
  shareWithFederatedRecipient: shareFileImpl,
};

export const nextcloudV32ShareWithFlowReceiverAdapter: ShareWithFlowReceiverAdapter = {
  key: "nextcloud/v32",
  acceptIncomingShare: acceptIncomingShareImpl,
  assertSharedFileContent: assertSharedFileContentImpl,
};

export const nextcloudV32ShareFileSenderAdapter: ShareFileSenderAdapter = {
  key: "nextcloud/v32",
  prepareShareFile: prepareShareFileImpl,
  sendFileToFederatedRecipient: shareFileImpl,
};

export const nextcloudV32ShareFileReceiverAdapter: ShareFileReceiverAdapter = {
  key: "nextcloud/v32",
  acceptIncomingShare: acceptIncomingShareImpl,
  assertSharedFileContent: assertSharedFileContentImpl,
};
