/**
 * @fileoverview
 * Cypress WAYF test: CERNBox v2 sender -> Nextcloud v33 recipient.
 *
 * Uses CERNBox v2 helpers on the sender side and Nextcloud v33 helpers
 * on the recipient side.
 */

import { getUtils } from "../utils/index.js";

describe("WAYF federated sharing: CERNBox to Nextcloud", () => {
  // Shared variables to avoid repetition and improve maintainability
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
  const recipientDisplayName =
    Cypress.env("NEXTCLOUD1_DISPLAY_NAME") || "michiel";
  const senderDomain = senderUrl.replace(/^https?:\/\/|\/$/g, "");
  const recipientDomain = recipientUrl.replace(/^https?:\/\/|\/$/g, "");

  const inviteLinkFileName = "wayf-cernbox-nc.txt";
  const sharedFileName = "wayf-cernbox-nc";
  const sharedFileContent = "";

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

  it("CERNBox sends OCM share via established WAYF contact to Nextcloud", () => {
    senderUtils.shareViaInviteLink({
      senderUrl,
      senderUsername,
      senderPassword,
      sharedFileName,
      sharedFileContent,
      recipientUsername,
    });
  });

  it("Nextcloud receives (or attempts to receive) OCM share from CERNBox", () => {
    recipientUtils.acceptInviteLinkShare({
      recipientUrl,
      recipientUsername,
      recipientPassword,
      sharedFileName,
    });
  });
});
