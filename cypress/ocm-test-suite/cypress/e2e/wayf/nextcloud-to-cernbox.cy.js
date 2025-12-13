/**
 * @fileoverview
 * Cypress WAYF test: Nextcloud v33 sender -> CERNBox v2 recipient.
 *
 * This mirrors the nextcloud-to-nextcloud WAYF flow but uses CERNBox v2
 * utils on the recipient side.
 */

import { getUtils } from "../utils/index.js";

describe("WAYF federated sharing: Nextcloud to CERNBox", () => {
  // Shared variables to avoid repetition and improve maintainability
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

  const inviteLinkFileName = "wayf-nc-cernbox.txt";
  const originalFileName = "welcome.txt";
  const sharedFileName = inviteLinkFileName;

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

  it("Nextcloud sends OCM share via established WAYF contact to CERNBox", () => {
    senderUtils.shareViaInviteLink({
      senderUrl,
      senderDomain,
      senderPlatform,
      senderUsername,
      senderPassword,
      recipientPlatform,
      recipientDomain,
      recipientUsername,
      recipientDisplayName,
      originalFileName,
      sharedFileName,
    });
  });

  it("CERNBox receives OCM share from Nextcloud (Files shared with me)", () => {
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
