/**
 * @fileoverview
 * Cypress code-flow test: Nextcloud v33 sender -> Nextcloud v33 recipient.
 *
 * Covers OCM code-flow by creating a file with known content on the sender,
 * sharing it with must-exchange-token (server-side), accepting it on the
 * recipient, reading it through the Nextcloud Files UI, and rendering final
 * evidence in the Cypress video.
 */

import { getUtils } from "../utils/index.js";

describe("Code-flow federated sharing: Nextcloud to Nextcloud", () => {
  const senderPlatform = Cypress.env("EFSS_PLATFORM_1") ?? "nextcloud";
  const recipientPlatform = Cypress.env("EFSS_PLATFORM_2") ?? "nextcloud";
  const senderVersion = Cypress.env("EFSS_PLATFORM_1_VERSION") ?? "v33";
  const recipientVersion = Cypress.env("EFSS_PLATFORM_2_VERSION") ?? "v33";
  const senderUrl =
    Cypress.env("NEXTCLOUD1_URL") || "https://nextcloud1.docker";
  const recipientUrl =
    Cypress.env("NEXTCLOUD2_URL") || "https://nextcloud2.docker";
  const senderUsername = Cypress.env("NEXTCLOUD1_USERNAME") || "einstein";
  const senderPassword = Cypress.env("NEXTCLOUD1_PASSWORD") || "relativity";
  const recipientUsername = Cypress.env("NEXTCLOUD2_USERNAME") || "michiel";
  const recipientPassword = Cypress.env("NEXTCLOUD2_PASSWORD") || "dejong";
  const senderDisplayName = Cypress.env("NEXTCLOUD1_DISPLAY_NAME") || "einstein";
  const recipientDisplayName =
    Cypress.env("NEXTCLOUD2_DISPLAY_NAME") || "michiel";
  const senderDomain = senderUrl.replace(/^https?:\/\/|\/$/g, "");
  const recipientDomain = recipientUrl.replace(/^https?:\/\/|\/$/g, "");

  const flowSlug = "code-flow-nc-nc";
  const inviteLinkFileName = `${flowSlug}.txt`;

  const senderUtils = getUtils(senderPlatform, senderVersion);
  const recipientUtils = getUtils(recipientPlatform, recipientVersion);

  it("Nextcloud creates WAYF invite and captures Nextcloud redirect URL", () => {
    senderUtils.createWayfInviteLink({
      senderUrl,
      senderUsername,
      senderPassword,
      recipientPlatform,
      recipientUrl,
      inviteLinkFileName,
    });
  });

  it("Nextcloud accepts WAYF invite from Nextcloud", () => {
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

  it("Nextcloud sends OCM code-flow share to Nextcloud", () => {
    senderUtils.shareViaCodeFlow({
      senderUrl,
      senderUsername,
      senderPassword,
      senderDomain,
      recipientUsername,
      recipientDisplayName,
      recipientDomain,
      flowSlug,
    });
  });

  it("Nextcloud accepts OCM code-flow share from Nextcloud", () => {
    recipientUtils.acceptCodeFlowShare({
      recipientUrl,
      recipientUsername,
      recipientPassword,
      flowSlug,
    });
  });

  it("Nextcloud reads OCM code-flow file from Nextcloud", () => {
    return recipientUtils
      .verifyCodeFlowContentRead({
        recipientUrl,
        recipientUsername,
        recipientPassword,
        flowSlug,
      })
      .then(({ sharedFileName: verifiedFileName, expectedContent }) => {
        recipientUtils.renderCodeFlowEvidence({
          sharedFileName: verifiedFileName,
          expectedContent,
        });
      });
  });
});
