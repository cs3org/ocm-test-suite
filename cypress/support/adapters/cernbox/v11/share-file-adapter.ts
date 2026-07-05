/// <reference types="cypress" />

import type {
  ShareFileReceiverAdapter,
  ShareFileSenderAdapter,
} from "../../../contracts/share-file";
import { makeCernboxFilesHelpers } from "../shared/files";
import { makeCernboxSharingHelpers } from "../shared/sharing";
import { cernboxV11Profile } from "./profile";

const files = makeCernboxFilesHelpers(cernboxV11Profile);
const sharing = makeCernboxSharingHelpers(cernboxV11Profile, files);

export const cernboxV11ShareFileSenderAdapter: ShareFileSenderAdapter = {
  key: "cernbox/v11",

  prepareShareFile({ sharedFileName, sourceFileName: _sourceFileName }) {
    files.ensureFilesAppActive();
    const content = `CERNBox share file: ${sharedFileName}`;
    files.createTextFile(sharedFileName, content);
    return cy.wrap({ expectedContent: content });
  },

  sendFileToFederatedRecipient({ sharedFileName, federatedRecipientId }) {
    files.ensureFilesAppActive();
    sharing.openSharingPanel(sharedFileName);
    sharing.addExternalShare(sharedFileName, federatedRecipientId);
  },
};

export const cernboxV11ShareFileReceiverAdapter: ShareFileReceiverAdapter = {
  key: "cernbox/v11",

  acceptIncomingShare({ sharedFileName }) {
    files.ensureFilesAppActive();
    sharing.acceptIncomingShare(sharedFileName);
  },

  assertSharedFileContent({ sharedFileName, expectedContent }) {
    files.ensureFilesAppActive();
    files.assertFileContent(sharedFileName, expectedContent);
  },
};
