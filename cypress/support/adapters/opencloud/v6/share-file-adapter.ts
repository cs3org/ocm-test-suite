/// <reference types="cypress" />

import type { ShareFileReceiverAdapter, ShareFileSenderAdapter } from "../../../contracts/share-file";
import { makeOpenCloudFilesHelpers } from "../shared/files";
import { makeOpenCloudSharingHelpers } from "../shared/sharing";
import { opencloudV6Profile } from "./profile";

const files = makeOpenCloudFilesHelpers(opencloudV6Profile);
const sharing = makeOpenCloudSharingHelpers(opencloudV6Profile, files);

export const opencloudV6ShareFileSenderAdapter: ShareFileSenderAdapter = {
  key: "opencloud/v6",

  prepareShareFile({ sharedFileName, sourceFileName: _sourceFileName }) {
    const content = `OpenCloud share file: ${sharedFileName}`;
    files.createTextFile(sharedFileName, content);
    return cy.wrap({ expectedContent: content });
  },

  sendFileToFederatedRecipient({ sharedFileName, federatedRecipientId }) {
    files.ensureFilesAppActive();
    sharing.addExternalShare(sharedFileName, federatedRecipientId);
  },
};

export const opencloudV6ShareFileReceiverAdapter: ShareFileReceiverAdapter = {
  key: "opencloud/v6",

  acceptIncomingShare({ sharedFileName }) {
    sharing.acceptIncomingShare(sharedFileName);
  },

  assertSharedFileContent({ sharedFileName, expectedContent }) {
    files.ensureFilesAppActive();
    files.assertFileContent(sharedFileName, expectedContent);
  },
};
