/**
 * @fileoverview
 * Cypress code-flow test: Nextcloud v33 sender -> CERNBox v2 recipient.
 *
 * Covers OCM code-flow by creating a file with known content on the sender,
 * sharing it with must-exchange-token (server-side), accepting it on the
 * recipient, reading it through the CERNBox editor, and rendering final
 * evidence in the Cypress video.
 */

import { getUtils } from "../utils/index.js";

describe("Code-flow federated sharing: Nextcloud to CERNBox", () => {
  const senderPlatform = Cypress.env("EFSS_PLATFORM_1") ?? "nextcloud";
  const recipientPlatform = Cypress.env("EFSS_PLATFORM_2") ?? "cernbox";
  const senderVersion = Cypress.env("EFSS_PLATFORM_1_VERSION") ?? "v33";
  const recipientVersion = Cypress.env("EFSS_PLATFORM_2_VERSION") ?? "v2";
  const senderUrl =
    Cypress.env("NEXTCLOUD1_URL") || "https://nextcloud1.docker";
  const recipientUrl = Cypress.env("CERNBOX1_URL") || "https://cernbox1.docker";
  const senderUsername = Cypress.env("NEXTCLOUD1_USERNAME") || "marie";
  const senderPassword = Cypress.env("NEXTCLOUD1_PASSWORD") || "radioactivity";
  const recipientUsername = Cypress.env("CERNBOX1_USERNAME") || "einstein";
  const recipientPassword = Cypress.env("CERNBOX1_PASSWORD") || "relativity";
  const senderDisplayName = Cypress.env("NEXTCLOUD1_DISPLAY_NAME") || "marie";
  const recipientDisplayName =
    Cypress.env("CERNBOX1_DISPLAY_NAME") || "Albert Einstein";
  const senderDomain = senderUrl.replace(/^https?:\/\/|\/$/g, "");
  const recipientDomain = recipientUrl.replace(/^https?:\/\/|\/$/g, "");

  const flowSlug = "code-flow-nc-cernbox";
  const inviteLinkFileName = `${flowSlug}.txt`;

  const senderUtils = getUtils(senderPlatform, senderVersion);
  const recipientUtils = getUtils(recipientPlatform, recipientVersion);

  it("Nextcloud creates WAYF invite and captures CERNBox redirect URL", () => {
    senderUtils.createWayfInviteLink({
      senderUrl,
      senderUsername,
      senderPassword,
      recipientPlatform,
      recipientUrl,
      inviteLinkFileName,
    });
  });

  it("CERNBox accepts WAYF invite from Nextcloud", () => {
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

  it("Nextcloud sends OCM code-flow share to CERNBox", () => {
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

  it("CERNBox accepts OCM code-flow share from Nextcloud", () => {
    recipientUtils.acceptCodeFlowShare({
      recipientUrl,
      recipientUsername,
      recipientPassword,
      flowSlug,
    });
  });

  it("CERNBox reads OCM code-flow file from Nextcloud", () => {
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
