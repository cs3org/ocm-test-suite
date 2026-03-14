/**
 * @fileoverview
 * Cypress code-flow test: CERNBox v2 sender -> Nextcloud v33 recipient.
 *
 * Proves OCM M6 token-exchange by creating a file with known content on
 * the sender, sharing it with must-exchange-token (server-side), accepting
 * on the recipient, reading back exact bytes via WebDAV, and rendering
 * final evidence in the Cypress video.
 */

import { getUtils } from "../utils/index.js";

describe("Code-flow federated sharing: CERNBox to Nextcloud", () => {
  const senderPlatform = Cypress.env("EFSS_PLATFORM_1") ?? "cernbox";
  const recipientPlatform = Cypress.env("EFSS_PLATFORM_2") ?? "nextcloud";
  const senderVersion = Cypress.env("EFSS_PLATFORM_1_VERSION") ?? "v2";
  const recipientVersion = Cypress.env("EFSS_PLATFORM_2_VERSION") ?? "v33";
  const senderUrl = Cypress.env("CERNBOX1_URL") || "https://cernbox1.docker";
  const recipientUrl =
    Cypress.env("NEXTCLOUD1_URL") || "https://nextcloud1.docker";
  const senderUsername = Cypress.env("CERNBOX1_USERNAME") || "einstein";
  const senderPassword = Cypress.env("CERNBOX1_PASSWORD") || "relativity";
  const recipientUsername = Cypress.env("NEXTCLOUD1_USERNAME") || "michiel";
  const recipientPassword = Cypress.env("NEXTCLOUD1_PASSWORD") || "dejong";
  const senderDisplayName =
    Cypress.env("CERNBOX1_DISPLAY_NAME") || "Albert Einstein";
  const senderDomain = senderUrl.replace(/^https?:\/\/|\/$/g, "");
  const recipientDomain = recipientUrl.replace(/^https?:\/\/|\/$/g, "");

  const inviteLinkFileName = "code-flow-cernbox-nc.txt";
  const testId = Date.now();
  const sharedFileName = `ocm-m6-proof-${testId}.txt`;
  const sharedFileContent = `ocm-m6-proof-${testId}`;

  const senderUtils = getUtils(senderPlatform, senderVersion);
  const recipientUtils = getUtils(recipientPlatform, recipientVersion);

  it("CERNBox creates WAYF invite and captures Nextcloud redirect URL", () => {
    senderUtils.createWayfInviteLink({
      senderUrl,
      senderUsername,
      senderPassword,
      recipientPlatform,
      recipientUrl,
      inviteLinkFileName,
    });
  });

  it("Nextcloud accepts WAYF invite from CERNBox", () => {
    recipientUtils.acceptWayfInviteLink({
      senderPlatform,
      senderDomain,
      senderUsername,
      senderDisplayName,
      recipientUrl,
      recipientDomain,
      recipientUsername,
      recipientPassword,
      inviteLinkFileName,
    });
  });

  it("CERNBox shares deterministic file for code-flow topology", () => {
    senderUtils.shareViaCodeFlow({
      senderUrl,
      senderUsername,
      senderPassword,
      sharedFileName,
      sharedFileContent,
      recipientUsername,
    });
  });

  it("Nextcloud accepts code-flow share", () => {
    recipientUtils.acceptCodeFlowShare({
      recipientUrl,
      recipientUsername,
      recipientPassword,
      sharedFileName,
    });
  });

  it("Nextcloud verifies file content and renders evidence", () => {
    return recipientUtils.verifyCodeFlowContentRead({
      recipientUrl,
      recipientUsername,
      recipientPassword,
      sharedFileName,
      expectedContent: sharedFileContent,
    }).then(({ sharedFileName: verifiedFileName, expectedContent }) => {
      recipientUtils.renderCodeFlowEvidence({
        sharedFileName: verifiedFileName,
        expectedContent,
      });
    });
  });
});
