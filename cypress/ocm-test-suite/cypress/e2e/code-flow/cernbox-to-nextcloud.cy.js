/**
 * @fileoverview
 * Cypress code-flow test: CERNBox v2 sender -> Nextcloud v33 recipient.
 *
 * Covers OCM code-flow by creating a file with known content on the sender,
 * sharing it with must-exchange-token (server-side), accepting it on the
 * recipient, downloading it through the Nextcloud Files UI, and rendering
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

  const flowSlug = "code-flow-cernbox-nc";
  const inviteLinkFileName = `${flowSlug}.txt`;

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

  it("CERNBox sends OCM code-flow share to Nextcloud", () => {
    senderUtils.shareViaCodeFlow({
      senderUrl,
      senderUsername,
      senderPassword,
      flowSlug,
      recipientUsername,
    });
  });

  it("Nextcloud accepts OCM code-flow share from CERNBox", () => {
    recipientUtils.acceptCodeFlowShare({
      recipientUrl,
      recipientUsername,
      recipientPassword,
      flowSlug,
    });
  });

  it("Nextcloud downloads OCM code-flow file from CERNBox", () => {
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
