/**
 * @fileoverview
 * Cypress WAYF test: CERNBox v2 sender -> CERNBox v2 recipient.
 *
 * This is structurally similar to the cross-platform WAYF tests but reuses
 * a single CERNBox v2 instance for both roles (see single-instance constraint).
 */

import { getUtils } from "../utils/index.js";

describe("WAYF federated sharing: CERNBox to CERNBox", () => {
  // Shared variables to avoid repetition and improve maintainability
  const senderPlatform = Cypress.env("EFSS_PLATFORM_1") ?? "cernbox";
  const recipientPlatform = Cypress.env("EFSS_PLATFORM_2") ?? "cernbox";
  const senderVersion = Cypress.env("EFSS_PLATFORM_1_VERSION") ?? "v2";
  const recipientVersion = Cypress.env("EFSS_PLATFORM_2_VERSION") ?? "v2";
  const senderUrl = Cypress.env("CERNBOX1_URL") || "https://cernbox1.docker";
  const recipientUrl = Cypress.env("CERNBOX2_URL") || "https://cernbox2.docker";
  const senderUsername = Cypress.env("CERNBOX1_USERNAME") || "einstein";
  const senderPassword = Cypress.env("CERNBOX1_PASSWORD") || "relativity";
  const recipientUsername = Cypress.env("CERNBOX2_USERNAME") || "marie";
  const recipientPassword = Cypress.env("CERNBOX2_PASSWORD") || "radioactivity";
  const senderDisplayName =
    Cypress.env("CERNBOX1_DISPLAY_NAME") || "Albert Einstein";
  const recipientDisplayName =
    Cypress.env("CERNBOX2_DISPLAY_NAME") || "Marie Curie";
  const senderDomain = senderUrl.replace(/^https?:\/\/|\/$/g, "");
  const recipientDomain = recipientUrl.replace(/^https?:\/\/|\/$/g, "");

  const inviteLinkFileName = "wayf-cernbox-cernbox.txt";
  const sharedFileName = "wayf-cernbox-cernbox";

  const senderUtils = getUtils(senderPlatform, senderVersion);
  const recipientUtils = getUtils(recipientPlatform, recipientVersion);

  it("Send invitation from CERNBox to CERNBox", () => {
    senderUtils.createWayfInviteLink({
      senderUrl,
      senderUsername,
      senderPassword,
      recipientPlatform,
      recipientUrl,
      inviteLinkFileName,
    });
  });

  it("Accept invitation from CERNBox to CERNBox", () => {
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

  it("CERNBox (sender) sends OCM share via established WAYF contact to CERNBox", () => {
    const sharedFileContent =
      Cypress.env("CERNBOX_SHARE_FILE_CONTENT_CB_CB") ||
      "WAYF CERNBox->CERNBox";

    senderUtils.shareViaInviteLink({
      senderUrl,
      senderUsername,
      senderPassword,
      sharedFileName,
      sharedFileContent,
      recipientUsername,
    });
  });

  it("CERNBox (recipient) receives OCM share from CERNBox", () => {
    recipientUtils.acceptInviteLinkShare({
      senderDisplayName,
      recipientUrl,
      recipientUsername,
      recipientPassword,
      recipientDisplayName,
      sharedFileName,
    });
  });
});
