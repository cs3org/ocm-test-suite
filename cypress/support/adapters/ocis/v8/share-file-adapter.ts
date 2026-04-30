/// <reference types="cypress" />

import type { ShareFileReceiverAdapter, ShareFileSenderAdapter } from "../../../contracts/share-file";
import { makeOcisFilesHelpers } from "../shared/files";
import { makeOcisSharingHelpers } from "../shared/sharing";
import { ocisV8Profile } from "./profile";

const files = makeOcisFilesHelpers(ocisV8Profile);
const sharing = makeOcisSharingHelpers(ocisV8Profile, files);

export const ocisV8ShareFileSenderAdapter: ShareFileSenderAdapter = {
  key: "ocis/v8",

  prepareShareFile({ sharedFileName, sourceFileName: _sourceFileName }) {
    const content = `OCM share file: ${sharedFileName}`;
    files.createTextFile(sharedFileName, content);
    return cy.wrap({ expectedContent: content });
  },

  sendFileToFederatedRecipient({ sharedFileName, federatedRecipientId }) {
    files.ensureFilesAppActive();
    sharing.addExternalShare(sharedFileName, federatedRecipientId);
  },
};

export const ocisV8ShareFileReceiverAdapter: ShareFileReceiverAdapter = {
  key: "ocis/v8",

  acceptIncomingShare({ sharedFileName }) {
    sharing.acceptIncomingShare(sharedFileName);
  },

  assertSharedFileContent({ sharedFileName, expectedContent }) {
    files.ensureFilesAppActive();
    files.assertFileContent(sharedFileName, expectedContent);
  },
};
