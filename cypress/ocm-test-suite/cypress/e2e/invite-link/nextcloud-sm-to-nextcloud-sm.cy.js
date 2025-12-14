/**
 * @fileoverview
 * Cypress test suite for testing invite link federated sharing via ScienceMesh functionality in Nextcloud.
 * This suite covers sending and accepting invitation links, sharing files via ScienceMesh,
 * and verifying that the shares are received correctly.
 *
 * @author Mohammad Mahdi Baghbani Pourvahid <mahdi@pondersource.com>
 */

import { getUtils } from "../utils/index.js";

describe("Invite link federated sharing via ScienceMesh functionality for Nextcloud", () => {
  // Shared variables to avoid repetition and improve maintainability
  const senderPlatform = Cypress.env("EFSS_PLATFORM_1") ?? "nextcloud";
  const recipientPlatform = Cypress.env("EFSS_PLATFORM_2") ?? "nextcloud";
  const senderVersion = Cypress.env("EFSS_PLATFORM_1_VERSION") ?? "v27";
  const recipientVersion = Cypress.env("EFSS_PLATFORM_2_VERSION") ?? "v27";
  const senderUrl =
    Cypress.env("NEXTCLOUD1_URL") || "https://nextcloud1.docker";
  const recipientUrl =
    Cypress.env("NEXTCLOUD2_URL") || "https://nextcloud2.docker";
  const senderUsername = Cypress.env("NEXTCLOUD1_USERNAME") || "einstein";
  const senderPassword = Cypress.env("NEXTCLOUD1_PASSWORD") || "relativity";
  const recipientUsername = Cypress.env("NEXTCLOUD2_USERNAME") || "michiel";
  const recipientPassword = Cypress.env("NEXTCLOUD2_PASSWORD") || "dejong";
  const senderDisplayName =
    Cypress.env("NEXTCLOUD1_DISPLAY_NAME") || "einstein";
  const recipientDisplayName =
    Cypress.env("NEXTCLOUD2_DISPLAY_NAME") || "michiel";
  const senderDomain = senderUrl.replace(/^https?:\/\/|\/$/g, "");
  const recipientDomain = recipientUrl.replace(/^https?:\/\/|\/$/g, "");
  const inviteLinkFileName = "invite-link-nc-nc.txt";
  const originalFileName = "welcome.txt";
  const sharedFileName = "invite-link-nc-nc.txt";

  // Get the right helper set for each side
  const senderUtils = getUtils(senderPlatform, senderVersion);
  const recipientUtils = getUtils(recipientPlatform, recipientVersion);

  /**
   * Test case: Sending an invitation link from sender to recipient.
   */
  it("Send invitation from Nextcloud to Nextcloud", () => {
    senderUtils.createInviteLink({
      senderUrl,
      senderUsername,
      senderPassword,
      recipientPlatform,
      recipientUrl,
      inviteLinkFileName,
    });
  });

  /**
   * Test case: Accepting the invitation link on the recipient's side.
   */
  it("Accept invitation from Nextcloud to Nextcloud", () => {
    recipientUtils.acceptInviteLink({
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

  /**
   * Test case: Sharing a file via ScienceMesh from sender to recipient.
   */
  it("Send ScienceMesh share of a <file> from Nextcloud to Nextcloud", () => {
    senderUtils.shareViaInviteLink({
      senderUrl,
      senderDomain,
      senderPlatform,
      senderUsername,
      senderPassword,
      recipientPlatform,
      recipientDomain,
      recipientDisplayName,
      originalFileName,
      sharedFileName,
    });
  });

  /**
   * Test case: Receiving and verifying the ScienceMesh share on the recipient's side.
   */
  it("Receive ScienceMesh share of a <file> from Nextcloud to Nextcloud", () => {
    recipientUtils.acceptInviteLinkShare({
      recipientUrl,
      recipientUsername,
      recipientPassword,
      sharedFileName,
    });
  });
});
