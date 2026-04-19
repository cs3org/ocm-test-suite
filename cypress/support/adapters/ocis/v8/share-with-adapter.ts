/// <reference types="cypress" />

import type {
  ShareWithReceiverAdapter,
  ShareWithSenderAdapter,
} from "../../../contracts/share-with";
import { expectedFileContent } from "../../../shared/content";
import { ocisV8Profile } from "./profile";
import { makeOcisFilesHelpers } from "../shared/files";
import { makeOcisSharingHelpers } from "../shared/sharing";

const filesHelpers = makeOcisFilesHelpers(ocisV8Profile);
const sharingHelpers = makeOcisSharingHelpers(ocisV8Profile, filesHelpers);

export const ocisV8ShareWithSenderAdapter: ShareWithSenderAdapter = {
  key: "ocis/v8",

  prepareShareFile({ sharedFileName }) {
    filesHelpers.ensureFilesAppActive();
    cy.log(`create share file: ${sharedFileName}`);
    filesHelpers.createTextFile(sharedFileName, expectedFileContent(sharedFileName));
    return cy.wrap({ expectedContent: expectedFileContent(sharedFileName) });
  },

  shareWithFederatedRecipient({ sharedFileName, federatedRecipientId }) {
    filesHelpers.ensureFilesAppActive();
    cy.log(`share ${sharedFileName} -> ${federatedRecipientId}`);
    sharingHelpers.openSharingPanel(sharedFileName);
    sharingHelpers.addExternalShare(sharedFileName, federatedRecipientId);
  },
};

export const ocisV8ShareWithReceiverAdapter: ShareWithReceiverAdapter = {
  key: "ocis/v8",

  acceptIncomingShare({ sharedFileName }) {
    filesHelpers.ensureFilesAppActive();
    sharingHelpers.acceptIncomingShare(sharedFileName);
  },

  assertSharedFileContent({ sharedFileName, expectedContent }) {
    filesHelpers.assertFileContent(sharedFileName, expectedContent);
  },
};
