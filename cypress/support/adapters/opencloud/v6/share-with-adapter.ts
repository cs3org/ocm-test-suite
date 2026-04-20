/// <reference types="cypress" />

import type {
  ShareWithReceiverAdapter,
  ShareWithSenderAdapter,
} from "../../../contracts/share-with";
import { expectedFileContent } from "../../../shared/content";
import { opencloudV6Profile } from "./profile";
import { makeOpenCloudFilesHelpers } from "../shared/files";
import { makeOpenCloudSharingHelpers } from "../shared/sharing";

const filesHelpers = makeOpenCloudFilesHelpers(opencloudV6Profile);
const sharingHelpers = makeOpenCloudSharingHelpers(opencloudV6Profile, filesHelpers);

export const opencloudV6ShareWithSenderAdapter: ShareWithSenderAdapter = {
  key: "opencloud/v6",

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

export const opencloudV6ShareWithReceiverAdapter: ShareWithReceiverAdapter = {
  key: "opencloud/v6",

  acceptIncomingShare({ sharedFileName }) {
    filesHelpers.ensureFilesAppActive();
    sharingHelpers.acceptIncomingShare(sharedFileName);
  },

  assertSharedFileContent({ sharedFileName, expectedContent }) {
    filesHelpers.assertFileContent(sharedFileName, expectedContent);
  },
};
